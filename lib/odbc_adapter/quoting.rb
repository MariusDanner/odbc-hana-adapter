module ODBCAdapter
  module Quoting
    # Quotes a string, escaping any ' (single quote) characters.
    def quote_string(string)
      string.gsub(/\\/, '\&\&').gsub(/'/, "''")
    end

    def quoted_true
      '1'
    end

    def unquoted_true
      1
    end

    def quoted_false
      '0'
    end

    def unquoted_false
      0
    end

    # Returns a quoted form of the column name.
    def quote_column_name(name)
      %["#{name.to_s.gsub('"', '""')}"]
    end

    # Ideally, we'd return an ODBC date or timestamp literal escape
    # sequence, but not all ODBC drivers support them.

    def quoted_date(value)
      if value.acts_like?(:time)
        zone_conversion_method = ActiveRecord::Base.default_timezone == :utc ? :getutc : :getlocal

        if value.respond_to?(zone_conversion_method)
          value = value.send(zone_conversion_method)
        end
        value.strftime('%Y-%m-%d %H:%M:%S') # Time, DateTime
      else
        value.strftime('%Y-%m-%d') # Date
      end
    end
  end
end
