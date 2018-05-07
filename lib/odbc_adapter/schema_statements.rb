module ODBCAdapter
  module SchemaStatements
    # Returns a Hash of mappings from the abstract data types to the native
    # database types. See TableDefinition#column for details on the recognized
    # abstract data types.
    def native_database_types
      @native_database_types ||= ColumnMetadata.new(self).native_database_types
    end

    # Returns an array of view names defined in the database.
    def views
      []
    end

    # Returns just a table's primary key
    def foreign_keys(table_name)
      stmt   = @connection.foreign_keys(native_case(table_name.to_s))
      result = stmt.fetch_all || []
      stmt.drop unless stmt.nil?

      result.map do |key|
        fk_from_table      = key[2]  # PKTABLE_NAME
        fk_to_table        = key[6]  # FKTABLE_NAME

        ActiveRecord::ConnectionAdapters::ForeignKeyDefinition.new(
          fk_from_table,
          fk_to_table,
          name:        key[11], # FK_NAME
          column:      key[3],  # PKCOLUMN_NAME
          primary_key: key[7],  # FKCOLUMN_NAME
          on_delete:   key[10], # DELETE_RULE
          on_update:   key[9]   # UPDATE_RULE
        )
      end
    end

    #---------------databases------------------

    def current_database
      database_metadata.database_name.strip
    end

    # these are duplicates of the schema statements
    def create_database(name, _options = {})
      execute("CREATE SCHEMA `#{name}`")
    end

    def drop_database(name)
      execute("DROP SCHEMA `#{name}`")
    end

    #---------------schemas--------------------

    def schemas
      select_values 'SELECT schema_name FROM schemas'
    end

    def create_schema(name)
      execute "CREATE SCHEMA \"#{name}\""
    end

    def drop_schema(name)
      execute "DROP SCHEMA \"#{name}\""
    end

    # rubocop:disable Naming/AccessorMethodName
    def set_schema(name)
      execute "SET SCHEMA \"#{name}\""
    end
    # rubocop:enable Naming/AccessorMethodName

    #---------------tables---------------------

    # Returns an array of table names, for database tables visible on the
    # current connection.
    def tables(_name = nil)
      stmt   = @connection.tables
      result = stmt.fetch_all || []
      stmt.drop

      result.each_with_object([]) do |row, table_names|
        schema_name, table_name, table_type = row[1..3]
        next if respond_to?(:table_filtered?) && table_filtered?(schema_name, table_type)
        table_names << format_case(table_name)
      end
    end

    def table_structure(table_name)
      exec_query("SELECT COLUMN_NAME, DEFAULT_VALUE, DATA_TYPE_NAME, IS_NULLABLE, CS_DATA_TYPE_NAME, LENGTH, SCALE FROM SYS.COLUMNS WHERE SCHEMA_NAME=\'#{@database}\' AND TABLE_NAME=\'#{table_name}\'").rows
    end

    def generic_table_definition(adapter = nil, table_name = nil, is_temporary = nil, options = {})
      if ::ActiveRecord::VERSION::MAJOR >= 4
        ActiveRecord::ConnectionAdapters::TableDefinition.new(table_name, is_temporary, options)
      else
        ActiveRecord::ConnectionAdapters::TableDefinition.new(adapter)
      end
    end

    def create_table(table_name, options = {})
      td = generic_table_definition(self, table_name, options[:temporary], options[:options])
      td.primary_key(options[:primary_key] || ActiveRecord::Base.get_primary_key(table_name.to_s.singularize)) unless options[:id] == false

      yield td if block_given?

      if options[:force] && table_exists?(table_name)
        drop_table(table_name, options)
      end

      create_sequence(default_sequence_name(table_name, nil))
      if ::ActiveRecord::VERSION::MAJOR >= 4
        create_sql = schema_creation.accept td
      else
        create_sql = 'CREATE TABLE '
        create_sql << "#{quote_table_name(table_name)} ("
        create_sql << td.to_sql
        create_sql << ") #{options[:options]}"
      end

      if options[:row]
        create_sql.insert(6, ' ROW')
      elsif options[:column]
        create_sql.insert(6, ' COLUMN')
      elsif options[:history]
        create_sql.insert(6, ' HISTORY COLUMN')
      elsif options[:global_temporary]
        create_sql.insert(6, ' GLOBAL TEMPORARY')
      elsif options[:local_temporary]
        create_sql.insert(6, ' GLOBAL LOCAL')
      else
        create_sql.insert(6, ' COLUMN')
      end
      execute create_sql
    end

    def rename_table(name, new_name)
      execute("RENAME TABLE #{quote_table_name(name)} TO #{quote_table_name(new_name)}")
      rename_sequence(table_name, new_name)
    end

    def drop_table(name, _options = {})
      execute("DROP TABLE #{quote_table_name(name)}")
      execute("DROP SEQUENCE #{quote_table_name(default_sequence_name(name, 0))}")
    end

    #--------------------columns-------------------

    # Returns an array of Column objects for the table specified by
    # +table_name+.
    def columns(table_name, _name = nil)
      return [] if table_name.blank?
      table_structure(table_name).each_with_object([]) do |col, cols|
        col_name        = col[0]  # SQLColumns: COLUMN_NAME
        col_default     = col[1]  # SQLColumns: COLUMN_DEF
        col_sql_type    = col[2]  # SQLColumns: DATA_TYPE
        col_nullable    = col[3]  # SQLColumns: IS_NULLABLE
        col_native_type = col[4]  # SQLColumns: TYPE_NAME
        col_limit       = col[5]  # SQLColumns: COLUMN_SIZE
        col_scale       = col[6]  # SQLColumns: DECIMAL_DIGITS

        args = { sql_type: col_sql_type, type: col_sql_type, limit: col_limit }
        args[:sql_type] = 'boolean' if col_native_type == self.class::BOOLEAN_TYPE

        if [ODBC::SQL_DECIMAL, ODBC::SQL_NUMERIC].include?(col_sql_type)
          args[:scale]     = col_scale || 0
          args[:precision] = col_limit
        end
        sql_type_metadata = ActiveRecord::ConnectionAdapters::SqlTypeMetadata.new(**args)
        cols << new_column(format_case(col_name), col_default, sql_type_metadata, col_nullable, table_name, col_native_type)
      end
    end

    def add_column(table_name, column_name, type, options = {})
      add_column_sql = "ALTER TABLE #{quote_table_name(table_name)} ADD ( #{quote_column_name(column_name)} #{type_to_sql(type, limit: options[:limit], precision: options[:precision], scale: options[:scale])}"
      add_column_sql << ')'
      execute(add_column_sql)
    end

    def change_column(table_name, column_name, type, options = {})
      unless options_include_default?(options)
        options[:default] = column_for(table_name, column_name).default
      end

      change_column_sql = "ALTER TABLE #{quote_table_name(table_name)} ALTER  (#{quote_column_name(column_name)} #{type_to_sql(type, limit: options[:limit], precision: options[:precision], scale: options[:scale])})"
      execute(change_column_sql)
    end

    def change_column_default(table_name, column_name, default_or_changes)
      default = extract_new_default_value(default_or_changes)
      column = column_for(table_name, column_name)
      change_column(table_name, column_name, column.sql_type, default: default)
    end

    def change_column_null(table_name, column_name, null, default = nil)
      column = column_for(table_name, column_name)

      unless null || default.nil?
        execute("UPDATE #{quote_table_name(table_name)} SET #{quote_column_name(column_name)}=#{quote(default)} WHERE #{quote_column_name(column_name)} IS NULL")
      end
      change_column(table_name, column_name, column.sql_type, null: null)
    end

    def rename_column(table_name, column_name, new_column_name)
      execute("RENAME COLUMN #{quote_table_name(table_name)}.#{quote_column_name(column_name)} to #{quote_column_name(new_column_name)}")
    end

    def remove_column(table_name, *column_names)
      if column_names.flatten!
        message = 'Passing array to remove_columns is deprecated, please use ' \
                  'multiple arguments, like: `remove_columns(:posts, :foo, :bar)`'
        ActiveSupport::Deprecation.warn message, caller
      end

      column_names.each do |column_name|
        execute "ALTER TABLE #{quote_table_name(table_name)} DROP (#{column_name})"
      end
    end

    #-------------------sequences--------------------------

    def create_sequence(sequence, _options = {})
      create_sql = "CREATE SEQUENCE #{quote_table_name(sequence)} INCREMENT BY 1 START WITH 1 NO CYCLE"
      execute create_sql
    end

    def rename_sequence(table_name, new_name)
      rename_sql =  "CREATE SEQUENCE #{quote_table_name(default_sequence_name(new_name, nil))} "
      rename_sql << 'INCREMENT BY 1 '
      rename_sql << "START WITH #{next_sequence_value(default_sequence_name(table_name, nil))} NO CYCLE"
      execute rename_sql
      drop_sequence(default_sequence_name(table_name, nil))
    end

    def drop_sequence(sequence)
      execute "DROP SEQUENCE #{quote_table_name(sequence)}"
    end

    #--------------------indexes----------------------------

    # Returns an array of indexes for the given table.
    def indexes(table_name, _name = nil)
      stmt   = @connection.indexes(native_case(table_name.to_s))
      result = stmt.fetch_all || []
      stmt.drop unless stmt.nil?

      index_cols = []
      index_name = nil
      unique     = nil

      result.each_with_object([]).with_index do |(row, indices), row_idx|
        # Skip table statistics
        next if row[6].zero? # SQLStatistics: TYPE

        if row[7] == 1 # SQLStatistics: ORDINAL_POSITION
          # Start of column descriptor block for next index
          index_cols = []
          unique     = row[3].zero? # SQLStatistics: NON_UNIQUE
          index_name = String.new(row[5]) # SQLStatistics: INDEX_NAME
        end

        index_cols << format_case(row[8]) # SQLStatistics: COLUMN_NAME
        next_row = result[row_idx + 1]

        if (row_idx == result.length - 1) || (next_row[6].zero? || next_row[7] == 1)
          indices << ActiveRecord::ConnectionAdapters::IndexDefinition.new(table_name, format_case(index_name), unique, index_cols)
        end
      end
    end

    # Ensure it's shorter than the maximum identifier length for the current
    # dbms
    def index_name(table_name, options)
      maximum = database_metadata.max_identifier_len || 255
      super(table_name, options)[0...maximum]
    end

    #------------------------keys-----------------------

    def primary_key(table_name)
      row = select_values "SELECT COLUMN_NAME FROM CONSTRAINTS WHERE SCHEMA_NAME=\'#{@database}\' AND TABLE_NAME=\'#{table_name}\' AND IS_PRIMARY_KEY=\'TRUE\'"
      (row && row.first) || default_primary_key
    end

    def default_primary_key
      quote_string('id')
    end
  end
end
