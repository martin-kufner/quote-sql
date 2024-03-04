# QuoteSql - Tool to build and run SQL queries easier
Creating SQL queries and proper quoting becomes complicated especially when you need advanced queries.

I created this library while coding for different projects, and had lots of Heredoc SQL queries, which pretty quickly became unreadable.

With QuoteSql you segment SQL Queries in readable junks, which can be individually tested and then combine them to the final query.
When us use RoR, you can combine queries or get the output with fields other than `pick` or `pluck`

Please have a look at the *unfinished* documentation below or run `QuoteSql.test` in a Ruby console

If you think QuoteSql is interesting but needs extension, let's chat!

If you run into problems, drop me a note.

Best Martin

## Caveats & Notes
- Currently its just built for Ruby 3, if you need Ruby 2, let me know.
- QuoteSql is used in production, but is still bleeding edge - and there is not a fully sync between doc and code.
- Just for my examples and in the docs, I'm using for Yajl for JSON parsing, and changed in my environments the standard parse output to *symbolized keys*.
- I've built this library as an addition to ActiveRecord and Arel, however you can use it with any sql database and plain Ruby.
- It is currently built for PostgreSQL only. If you want to use other DBs, please contribute your code!

## Examples
### Simple quoting
`QuoteSql.new("SELECT %field").quote(field: "abc").to_sql`
  => SELECT 'abc'

`QuoteSql.new("SELECT %field::TEXT").quote(field: 9).to_sql`
=> SELECT 9::TEXT

### Rails models
`QuoteSql.new(Users.limit(10).select("%columns")).quote(columns: ['first_name', 'last_name').to_sql` 
=> SELECT first_name, last_name FROM users LIMIT 10

### Quoting of columns and table from a model - or an object responding to table_name and column_names or columns
`QuoteSql.new("SELECT %columns FROM %table").quote(table: User).to_sql`
  => SELECT "id",firstname","lastname",... FROM "users"
  
### Injecting raw sql in a query
`QuoteSql.new("SELECT a,b,%raw FROM my_table").quote(raw: "jsonb_build_object('a', 1)").to_sql`
  => SELECT "a,b,jsonb_build_object('a', 1) FROM my_table

### Injecting ActiveRecord, Arel.sql or QuoteSql
`QuoteSql.new("SELECT %column_names FROM (%any_name) a").
    quote(any_name: User.select("%column_names").where(id: 3), column_names: [:firstname, :lastname]).to_sql`
  => SELECT firstname, lastname FROM (SELECT firstname, lastname FROM users where id = 3)

### Insert of values quoted and sorted with columns
Values are be ordered in sequence of columns. Missing value entries are substitured with DEFAULT.
`QuoteSql.new("INSERT INTO %table (%columns) VALUES %values ON CONFLICT (%constraint) DO NOTHING").
    quote(table: User, values: [
      {firstname: "Albert", id: 1, lastname: "Müller"},
      {lastname: "Schultz", firstname: "herbert"}
    ], constraint: :id).to_sql`
  => INSERT INTO "users" ("id", "firstname", "lastname", "created_at")
      VALUES
        (1, 'Albert', 'Müller', DEFAULT), 
        (DEFAULT, 'herbert', 'Schultz', DEFAULT)
      ON CONFLICT ("id") DO NOTHING
      
### Columns from a list
`QuoteSql.new("SELECT %columns FROM %table").quote(table: "foo", columns: [:a, "b", "foo.c", {d: :e}]).to_sql`
  => SELECT "foo"."a","b"."foo"."c", "foo"."e" AS d

## Executing
### Getting the results
  `QuoteSql.new('SELECT %x AS a').quote(x: 1).result`
    => [{:a=>1}]

### Binds
You can use binds ($1, $2, ...) in the SQL and add arguments to the result call
  `QuoteSql.new('SELECT $1 AS a').result(1)`  
    => [{:a=>1}]

#### using JSON

    v = {a: 1, b: "foo", c: true}
    QuoteSQL(%q{SELECT * FROM %x_json}, x_json: 1, x_casts: {a: "int", b: "text", c: "boolean"}).result(v.to_json)
    
  => SELECT * FROM json_to_recordset($1) AS "x"("a" int,"b" text,"c" boolean) => [{a: 1, b: "foo", c: true}]

Insert fom json
  
    v = {a: 1, b: "foo", c: true}
    QuoteSql.new("INSERT INTO table (%columns) SELECT * FROM %json").quote({:json=>1}).result(v.to_json)




## Substitution of mixins with quoted values 
  In the SQL matches of `%foo` or `%{foo}` or `%foo_4_bar` or `%{foo_4_bar}` the *"mixins"*
  are substituted with quoted values
  the values are looked up from the options given in the quotes method
  the mixins can be recursive.
  **Caution! You need to take care, no protection against infinite recursion **
  
### Special mixins
- `%table` +String+, +ActiveRecord::Base+, Object responding to #to_sql, and +Array+ of these
- `%columns` +Array+ of +String+, +Hash+ keys: AS +Symbol+, +String+. fallback: 1) %casts keys, 2) %table.columns 
- `%casts` +Hash+ keys: column name, values: Cast e.g. "text", "integer"
- `%ident` | `%constraint` | `%constraints` quoting for database columns
- `%raw` | `%sql` inserting raw SQL
- `%values` creates the value section for INSERT `INSERT INTO foo (a,b) %values`
- `%x_values` creates the value secion for FROM `SELECT column1, column2, column3 FROM %x_values`
- `%x_json` creates `json_for_recordset(JSON) x (CASTS)`. "x" can be any other identifier, you need to define the casts e.g. `quotes(x_json: {a: "a", b: 1}, x_casts: {a: :text, b: :integer)`

All can be preceded by additional letters and underscore e.g. `%foo_bar_column`

### Type casts
A database typecast is added to fields ending with double underscore and a valid db data type
with optional array dimension

- `%field::jsonb` => treats the field as jsonb when casted
- `%array::text[]` => treats an array like a text array, default is JSONB

### Quoting
- Any value of the standard mixins are quoted with these exceptions
- +Array+ are quoted as DB Arrays unless a type cast is given e.g. __jsonb
- +Hash+ are quoted as jsonb unless a type cast is given e.g. __json
- When the value responds to :to_sql or is a +Arel::Nodes::SqlLiteral+ its added as raw SQL
- +Proc+ are executed with the +QuoteSQL::Quoter+ object as parameter and added as raw SQL

### Special quoting for %columns

    `QuoteSql.new("SELECT %columns FROM %table, other_table").quote(columns: ["a", "other_table.a", :a ], table: "my_table")`
    => SELECT "a", "other_table"."a", "my_table"."a" from "my_table", "other_table"

- +String+ without a dot  e.g. "firstname" => "firstname"
- +String+ containing a dot e.g. "users.firstname" or => "users"."firstname"
- +Symbol+ prepended with table from table: quote if present.
- +Proc+ is called in the current context
- +QuoteSql::Raw+ or +Arel::Nodes::SqlLiteral+ are injected as is
- Object responding to #to_sql is called and injected 
- +Array+
  - +Hash+ see below
  - other see above
- +Hash+
  - keys become the "AS"
  - values
    - +Hash+, +Array+ casted as JSONB
    - others see above
    


## Shortcuts and functions
- `QuoteSQL("select %abc", abc: 1)` == `QuoteSql.new("select %abc").quote(abc: 1)`
- when you have in your initializer `String.include QuoteSql::Extension` you can do e.g. `"select %abc".quote_sql(abc: 1)`
- when you have in your initializer `ActiveRecord::Relation.include QuoteSql::Extension` you can do e.g.  `Profile.limit(10).select('%abc').quote_sql(abc: 1)`

## Debug and dump
If you have pg_format installed you can get the resulting query inspected: 
  `QuoteSql.new("select %abc").quote(abc: 1).dsql`

# Test
Currently there are just minimal tests
run `QuoteSql.test`
You can find them in /lib/quote_sql/test.rb

## Installing
`gem install quote-sql`
or in Gemfile
`gem 'quote-sql'`

### Ruby on Rails
Add this to config/initializers/quote_sql.rb

    ActiveSupport.on_load(:active_record) do
      require 'quote_sql'
      
      # if you want to execute from Strings 
      #   e.g. "select %a".quote_sql(a: 1).result
      String.include QuoteSql::Extension

      # if you use Active Record 
      QuoteSql.db_connector = ActiveRecord::Base
      # if you want to execute from a Model 
      #   e.g. User.select("name, %a").quote_sql(a: 1).result
      ActiveRecord::Relation.include QuoteSql::Extension
    end  

## Todos
- Functionalities not yet used in my production might not work
- More documentation
- Tests missing
- Missing functionalities
  - Prepare
  - which other - let me know!
