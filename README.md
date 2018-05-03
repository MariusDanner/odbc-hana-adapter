# ODBCAdapter

[![Gem](https://img.shields.io/gem/v/odbc_adapter.svg)](https://rubygems.org/gems/odbc_adapter)

An ActiveRecord ODBC adapter. Master branch is working off of Rails 5.0.1.

This adapter will work for SAP HANA and it may be able to do basic querying for other DBMSes

This adapter is a merge of [Localytics ODBC Adapter](https://github.com/localytics/odbc_adapter) and [SAPs ActiveRecord-HANA-Adapter](https://github.com/SAP/activerecord-hana-adapter)

## Installation

Ensure you have the ODBC driver installed on your machine.

Add this line to your application's Gemfile:

```ruby
gem 'odbc_adapter'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install odbc_adapter

## Usage

Configure your `database.yml` by either using the `dsn` option to point to a DSN that corresponds to a valid entry in your `~/.odbc.ini` file:

```
development:
  adapter:  odbc
  dsn: MyDatabaseDSN
```

or by using the `conn_str` option and specifying the entire connection string:

```
development:
  adapter: odbc
  conn_str: "DRIVER=/usr/lib/libodbcHDB.so;SERVER=localhost;PORT=30015;DATABASE=my_database;"
```

ActiveRecord models that use this connection will now be connecting to the configured database using the ODBC driver.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/MariusDanner/odbc-hana-adapter.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
