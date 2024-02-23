Dir.glob(__FILE__.sub(/\.rb$/, "/*.rb")).each { require(_1) unless _1[/test\.rb$/] }

# Tool to build and run SQL queries easier
#
#   QuoteSql.new("SELECT %field").quote(field: "abc").to_sql
#   => SELECT 'abc'
#
#   QuoteSql.new("SELECT %field__text").quote(field__text: 9).to_sql
#   => SELECT 9::TEXT
#
#   QuoteSql.new("SELECT %columns FROM %table_name").quote(table: User).to_sql
#   => SELECT "id",firstname","lastname",... FROM "users"
#
#   QuoteSql.new("SELECT a,b,%raw FROM table").quote(raw: "jsonb_build_object('a', 1)").to_sql
#   => SELECT "a,b,jsonb_build_object('a', 1) FROM table
#
#   QuoteSql.new("SELECT %column_names FROM (%any_name) a").
#     quote(any_name: User.select("%column_names").where(id: 3), column_names: [:firstname, :lastname]).to_sql
#   => SELECT firstname, lastname FROM (SELECT firstname, lastname FROM users where id = 3)
#
#   QuoteSql.new("INSERT INTO %table (%columns) VALUES %values ON CONFLICT (%constraint) DO NOTHING").
#     quote(table: User, values: [
#       {firstname: "Albert", id: 1, lastname: "Müller"},
#       {lastname: "Schultz", firstname: "herbert"}
#     ], constraint: :id).to_sql
#   => INSERT INTO "users" ("id", "firstname", "lastname", "created_at")
#       VALUES (1, 'Albert', 'Müller', CURRENT_TIMESTAMP), (DEFAULT, 'herbert', 'Schultz', CURRENT_TIMESTAMP)
#       ON CONFLICT ("id") DO NOTHING
#
#   QuoteSql.new("SELECT %columns").quote(columns: [:a, :"b.c", c: "jsonb_build_object('d', 1)"]).to_sql
#   => SELECT "a","b"."c",jsonb_build_object('d', 1) AS c
#
# Substitution
#   In the SQL matches of %foo or %{foo} or %foo_4_bar or %{foo_4_bar} the *"mixins"*
#   are substituted with quoted values
#   the values are looked up from the options given in the quotes method
#   the mixins can be recursive, Caution! You need to take care, you can create infintive loops!
#
# Special mixins are
# - %table | %table_name | %table_names
# - %column | %columns | %column_names
# - %ident | %constraint | %constraints quoting for database columns
# - %raw | %sql inserting raw SQL
# - %value | %values creates value section for e.g. insert
#   - In the right order
#     - Single value => (2)
#     - +Array+ => (column, column, column) n.b. has to be the correct order
#     - +Array+ of +Array+ => (...),(...),(...),...
#   - if the columns option is given (or implicitely by setting table)
#     - +Hash+ values are ordered according to the columns option, missing values are replaced by DEFAULT
#     - +Array+ of +Hash+ multiple record insert
# - %bind is replaced with the current bind sequence.
#   Without appended number the first %bind => $1, the second => $2 etc.
#   - %bind\\d+ => $+Integer+ e.g. %bind7 => $7
#   - %bind__text => $1 and it is registered as text - this is used in prepared statements TODO
#   - %key_bind__text => $1 and it is registered as text when using +Hash+ in the execute
#     $1 will be mapped to the key's value in the +Hash+ TODO
#
# All can be preceded by additional letters and underscore e.g. %foo_bar_column
#
# A database typecast is added to fields ending with double underscore and a valid db data type
# with optional array dimension
#
# - %field__jsonb => adds a ::JSONB typecast to the field
# - %number_to__text => adds a ::TEXT typecast to the field
# - %array__text1 => adds a ::TEXT[] TODO
# - %array__text2 => adds a ::TEXT[][] TODO
#
# Quoting
# - Any value of the standard mixins are quoted with these exceptions
# - +Array+ are quoted as DB Arrays unless the type cast e.g. __jsonb is given
# - +Hash+ are quoted as jsonb
# - When the value responds to :to_sql or is a +Arel::Nodes::SqlLiteral+ its added as raw SQL
# - +Proc+ are executed with the +QuoteSQL::Quoter+ object as parameter and added as raw SQL
#
# Special quoting columns
# - +String+ or +Symbol+ without a dot  e.g. :firstname => "firstname"
# - +String+ or +Symbol+ containing a dot e.g. "users.firstname" or => "users"."firstname"
# - +Array+
#   - +String+ and +Symbols+ see above
#   - +Hash+ see below
# - +Hash+ or within the +Array+
#   - +Symbol+ value will become the column name e.g. {table: :column} => "table"."column"
#   - +String+ value will become the expression, the key the AS {result: "SUM(*)"} => SUM(*) AS result
#   - +Proc+ are executed with the +QuoteSQL::Quoter+ object as parameter and added as raw SQL
#
class QuoteSql
  DATA_TYPES_RE = %w(
(?:small|big)(?:int|serial)
bit bool(?:ean)? box bytea cidr circle date
(?:date|int[48]|num|ts(?:tz)?)(?:multi)?range
macaddr8?
jsonb?
ts(?:query|vector)
float[48] (?:int|serial)[248]?
double_precision  inet
integer  line lseg   money   path pg_lsn
pg_snapshot point polygon real  text timestamptz timetz
txid_snapshot uuid xml
(bit_varying|varbit|character|char|character varying|varchar)(_\\(\\d+\\))?
(numeric|decimal)(_\\(\d+_\d+\\))?
interval(_(YEAR|MONTH|DAY|HOUR|MINUTE|SECOND|YEAR_TO_MONTH|DAY_TO_HOUR|DAY_TO_MINUTE|DAY_TO_SECOND|HOUR_TO_MINUTE|HOUR_TO_SECOND|MINUTE_TO_SECOND))?(_\\(\d+\\))?
time(stamp)?(_\\(\d+\\))?(_with(out)?_time_zone)?
    ).join("|")

  CASTS = Regexp.new("__(#{DATA_TYPES_RE})$", "i")

  def self.conn
    raise ArgumentError, "You need to define a database connection function"
  end

  def self.db_connector=(conn)
    Connector.set(conn)
  end

  def initialize(sql = nil)
    @original = sql.respond_to?(:to_sql) ? sql.to_sql : sql.to_s
    @sql = @original.dup
    @quotes = {}
    @resolved = {}
    @binds = []
  end

  attr_reader :sql, :quotes, :original, :binds
  attr_writer :table_name, :column_names

  def table_name
    return @table_name if @table_name
    return unless table = @quote&.dig(:table)
    @table_name = table.respond_to?(:table_name) ? table.table_name : table.to_s
  end

  def column_names
    return @column_names if @column_names
    return unless columns = @quote&.dig(:columns)
    @column_names = if columns[0].is_a? String
      columns
    else
      columns.map(&:name)
    end.map(&:to_s)
  end

  # Add quotes keys are symbolized
  def quote(quotes1 = {}, **quotes2)
    quotes = @quotes.merge(quotes1, quotes2).transform_keys(&:to_sym)
    if table = quotes.delete(:table)
      columns = quotes.delete(:columns) || table.columns
    end
    @quotes = { table:, columns:, **quotes }
    self
  end

  class Error < ::RuntimeError
    def initialize(quote_sql)
      @object = quote_sql
    end

    def message
      super + %Q@<QuoteSql #{@object.original.inspect} #{@object.errors.inspect}>@
    end
  end

  def to_sql
    mixin!
    raise Error.new(self) if errors?
    return Arel.sql @sql if defined? Arel
    @sql
  end

  def result(binds = [], prepare: false, async: false)
    sql = to_sql
    if binds.present? and sql.scan(/(?<=\$)\d+/).map(&:to_i).max + 1 != binds.length
      raise ArgumentError, "Wrong number of binds"
    end
    _exec(sql, binds, prepare: false, async: false)
  rescue => exc
    STDERR.puts exc.sql
    raise exc
  end

  alias exec result

  def prepare(name)
    sql = to_sql
    raise ArguemntError, "binds not all casted e.g. %bind__CAST" if @binds.reject.any?
    name = quote_column_name(name)
    _exec_query("PREPARE #{name} (#{@binds.join(',')}) AS #{sql}")
    @prepare_name = name
  end


  # Executes a prepared statement
  # Processes in batches records
  # returns the array of the results depending on RETURNING is in the query
  #
  #   execute([1, "a", true, nil], ...)
  #
  #   execute({ id: 1, text: "a", bool: true, know: nil}, ...)
  #
  #   execute([1, "a", true, nil], ... batch: 500)
  #   # set the batch size of 500
  #
  #   execute([1, "a", true, nil], ... batch: falss)
  #   # processes all at once
  def execute(*records, batch: 1000)
    sql = "EXECUTE #{@prepare_name}(#{(1..@binds.length).map { "$#{_1}" }.join(",")})"
    records.map! do |record|
      if record.is_a?(Hash)
        raise NotImplementedError, "record hash not yet implemented"
      else
        record = Array(record)
      end
      if @binds.length != record.length
        next RuntimeError.new("binds are not equal arguments, #{record.inspect}")
      end
      _exec(sql, record, prepare: false, async: false)
    end
  end

  def reset
    @sql = @original
  end

  def errors
    @quotes.to_h do |k, v|
      r = @resolved[k]
      next [nil, nil] unless r.nil? or r.is_a?(Exception)
      [k, "#{@quotes[k].inspect} => #{v.inspect}"]
    end.compact
  end

  def errors?
    @resolved.any? { _2.is_a? Exception }
  end

  MIXIN_RE = /(%\{?([a-z][a-z0-9_]*)}|%([a-z][a-z0-9_]*)\b)/im

  def key_matches
    @sql.scan(MIXIN_RE).map do |full, *key|
      key = key.compact[0]
      [full, key, @quotes.key?(key.to_sym)]
    end
  end

  def mixin!
    unresolved = Set.new(key_matches.map(&:second))
    last_unresolved = Set.new
    loop do
      s = StringScanner.new(@sql)
      sql = ""
      key_matches.each do |key_match, key, has_quote|
        s.scan_until(/(.*?)#{key_match}([a-z0-9_]*)/im)
        matched, pre, post = s.matched, s[1], s[2]
        if m = key.match(/^bind(\d+)?(?:#{CASTS})?$/im)
          if m[2].present?
            cast = m[2].tr("_", " ")
          end
          if m[1].present?
            bind_num = m[1].to_i
            @binds[bind_num - 1] ||= cast
            raise "cast #{bind_num} already set to #{@binds[bind_num - 1]}" unless @binds[bind_num - 1] == cast
          else
            @binds << cast
            bind_num = @binds.length
          end
          matched = "#{pre}$#{bind_num}#{post}"
        elsif has_quote
          quoted = quoter(key)
          unresolved.delete key
          if (i = quoted.scan MIXIN_RE).present?
            unresolved += i.map(&:last)
          end
          matched = "#{pre}#{quoted}#{post}"
        end
      rescue TypeError
      ensure
        sql << matched.to_s
      end
      @sql = sql + s.rest
      break if unresolved.empty?
      break if unresolved == last_unresolved
      last_unresolved = unresolved.dup
    end
    self
  end

  def quoter(key)
    quoter = @resolved[key.to_sym] = Quoter.new(self, key, @quotes[key.to_sym])
    quoter.to_sql
  rescue TypeError => exc
    @resolved[key.to_sym] = exc
    raise exc
  end

  extend Quoting

end

QuoteSql.include QuoteSql::Formater

class Array
  def depth
    select { _1.is_a?(Array) }.map { _1.depth.to_i + 1 }.max || 1
  end
end

