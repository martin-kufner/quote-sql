# QuoteSql - Tool to build and run SQL queries easier
I've built this library as an addition to ActiveRecord and Arel, however you can use it with any sql database and plain Ruby.
However currently it is just used with PostgreSQL.

Creating SQL queries and proper quoting becomes complicated especially when you need advanced queries.

I created this library while coding for different projects, and had lots of Heredoc SQL queries, which pretty quickly becomes the kind of: 
> When I wrote these lines of code, just me and God knew what they mean. Now its just God.

My strategy is to segment SQL Queries in readable junks, which can be individually tested and then combine their sql to the final query.

QuoteSql is used in production, but is still bleeding edge.

If you think QuoteSql is interesting, let's chat!
Also if you have problems using it, just drop me a note.

Best Martin

## Examples
### Simple quoting
`QuoteSql.new("SELECT %field").quote(field: "abc").to_sql`
  => SELECT 'abc'

`QuoteSql.new("SELECT %field__text").quote(field__text: 9).to_sql`
=> SELECT 9::TEXT

### Quoting of columns and table from a model - or an object responding to table_name and column_names or columns
`QuoteSql.new("SELECT %columns FROM %table_name").quote(table: User).to_sql`
  => SELECT "id",firstname","lastname",... FROM "users"
### Injecting raw sql in a query
`QuoteSql.new("SELECT a,b,%raw FROM table").quote(raw: "jsonb_build_object('a', 1)").to_sql`
  => SELECT "a,b,jsonb_build_object('a', 1) FROM table

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
      VALUES (1, 'Albert', 'Müller', CURRENT_TIMESTAMP), (DEFAULT, 'herbert', 'Schultz', CURRENT_TIMESTAMP)
      ON CONFLICT ("id") DO NOTHING
      
### Columns from a list
`QuoteSql.new("SELECT %columns").quote(columns: [:a, :"b.c", c: "jsonb_build_object('d', 1)"]).to_sql`
  => SELECT "a","b"."c",jsonb_build_object('d', 1) AS c

### Execution of a query
`QuoteSql.new("Select 1 as abc").result` => [{:abc=>1}]


## Substitution of mixins with quoted values 
  In the SQL matches of `%foo` or `%{foo}` or `%foo_4_bar` or `%{foo_4_bar}` the *"mixins"*
  are substituted with quoted values
  the values are looked up from the options given in the quotes method
  the mixins can be recursive.
  **Caution! You need to take care, no protection against infinite recursion **
  
### Special mixins
- `%table` | `%table_name` | `%table_names`
- `%column` | `%columns` | `%column_names`
- `%ident` | `%constraint` | `%constraints` quoting for database columns
- `%raw` | `%sql` inserting raw SQL
- `%value` | `%values` creates value section for e.g. insert
  - In the right order
    - Single value => (2)
    - +Array+ => (column, column, column) n.b. has to be the correct order
    - +Array+ of +Array+ => (...),(...),(...),...
  - if the columns option is given (or implicitely by setting table)
    - +Hash+ values are ordered according to the columns option, missing values are replaced by `DEFAULT`
    - +Array+ of +Hash+ multiple record insert
- `%bind` is replaced with the current bind sequence.
  Without appended number the first %bind => $1, the second => $2 etc.
  - %bind\\d+ => $+Integer+ e.g. `%bind7` => $7
  - `%bind__text` => $1 and it is registered as text - this is used in prepared statements (TO BE IMPLEMENTED)
  - `%key_bind__text` => $1 and it is registered as text when using +Hash+ in the execute
    $1 will be mapped to the key's value in the +Hash+ TODO

All can be preceded by additional letters and underscore e.g. `%foo_bar_column`

### Type casts
A database typecast is added to fields ending with double underscore and a valid db data type
with optional array dimension

- `%field__jsonb` => adds a `::JSONB` typecast to the field
- `%number_to__text` => adds a `::TEXT` typecast to the field
- `%array__text1` => adds a `::TEXT[]` (TO BE IMPLEMENTED)
- `%array__text2` => adds a `::TEXT[][]` (TO BE IMPLEMENTED)

### Quoting
- Any value of the standard mixins are quoted with these exceptions
- +Array+ are quoted as DB Arrays unless a type cast is given e.g. __jsonb
- +Hash+ are quoted as jsonb unless a type cast is given e.g. __json
- When the value responds to :to_sql or is a +Arel::Nodes::SqlLiteral+ its added as raw SQL
- +Proc+ are executed with the +QuoteSQL::Quoter+ object as parameter and added as raw SQL

### Special quoting columns
- +String+ or +Symbol+ without a dot  e.g. :firstname => "firstname"
- +String+ or +Symbol+ containing a dot e.g. "users.firstname" or => "users"."firstname"
- +Array+
  - +String+ and +Symbols+ see above
  - +Hash+ see below
- +Hash+ or within the +Array+
  - +Symbol+ value will become the column name e.g. {table: :column} => "table"."column"
  - +String+ value will become the expression, the key the AS {result: "SUM(*)"} => SUM(*) AS result
  - +Proc+ are executed with the +QuoteSQL::Quoter+ object as parameter and added as raw SQL

## Installing
`gem install quote-sql`
or in Gemfile
`gem 'quote-sql'`

### Ruby on Rails
Add this to config/initializers/quote_sql.rb

    ActiveSupport.on_load(:active_record) do
      require 'quote_sql'
      QuoteSql.db_connector = ActiveRecord::Base
      String.include QuoteSql::Extension
      ActiveRecord::Relation.include QuoteSql::Extension
    end  

## Todos
- Functionalities not yet used in my production might not work
- More documentation
- Tests missing
- Missing functionalities
  - Prepare
  - which other - let me know!
