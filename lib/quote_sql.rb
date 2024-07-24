Dir.glob(__FILE__.sub(/\.rb$/, "/*.rb")).each { require(_1) unless _1[/(deprecated|test)\.rb$/] }

# Tool to build and run SQL queries easier
class QuoteSql

  DATA_TYPES_RE = %w(
(?>character\\s+varying|bit\\s+varying|character|varbit|varchar|char|bit|interval)(?>\\s*\\(\\s*\\d+\\s*\\))?
(?>numeric|decimal)(?>\\s*\\(\\s*\\d+\\s*,\\s*\\d+\\s*\\))?
timestamptz timetz
time(?>stamp)?(?>\\s*\\(\\s*\\d+\\s*\\))?(?>\\s+with(?>out)?\\s+time\\s+zone)?
integer
(?>small|big)(?>int|serial)
bool(?>ean)? box bytea cidr circle date
(?:date|int[48]|num|ts(?:tz)?)(?:multi)?range
macaddr8?
ts(?>query|vector)
float[48]
(?:int|serial)[248]?
double\\s+precision
jsonb json
 inet
line lseg   money   path
pg_lsn pg_snapshot txid_snapshot
point polygon real text
uuid xml hstore
    ).join("|")

  CASTS = Regexp.new("::(#{DATA_TYPES_RE})((?:\\s*\\[\\s*\\d?\\s*\\])*)", "i")

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

    @tables = {}
    @columns = {}
    @casts = {}
  end

  attr_reader :sql, :quotes, :original, :binds, :tables, :columns

  def table(name = nil)
    table = @tables[name&.to_sym]
    table.is_a?(Class) ? table : table.dup
  end

  def table=(value)
    name, table = value
    name = name&.to_sym
    @tables[name] = table
    if table.respond_to?(:columns)
      @casts[name] = table.columns.to_h do |c|
        [c.name.to_sym, { sql_type: c.sql_type, default: (c.default || c.default_function rescue nil).present?, virtual: c.type == :virtual }]
      end if @casts[name].blank?
    elsif table.respond_to?(:column_names)
      @casts[name] = table.column_names.to_h { [_1.to_sym, nil] } if @casts[name].blank?
    end
  end

  alias tables= table=

  def column=(value)
    name, column = value
    name = name&.to_sym
    @columns[name] = column
  end

  alias columns= column=

  def cast=(value)
    name, cast = value
    name = name&.to_sym
    raise ArgumentError unless cast.is_a?(Hash)
    (@casts[name] ||= {}).update(cast.transform_values { _1.is_a?(Hash) ? _1 : { sql_type: _1 } })
  end

  alias casts= cast=

  def columns(name = nil, value=nil)
    name = name&.to_sym
    if name.present? and value.present?
      @columns[name] = value
    else
      @columns[name] || @casts[name]&.keys&.map(&:to_s)
    end
  end

  def casts(name = nil)
    @casts.fetch(name&.to_sym) { @casts[nil] }
  end

  # Add quotes keys are symbolized
  def quote(quotes = {})
    quotes = quotes.transform_keys(&:to_sym)
    re = /(?:^|(.*)_)(table|columns|casts)$/i
    (table_name = quotes[:table_name].presence) and (@tables[:table] ||= table_name)
    quotes.keys.grep(re).each do |quote|
      _, name, type = quote.to_s.match(re)&.to_a
      value = quotes.delete quote
      value = Raw.sql(value) if value.class.to_s == "Arel::Nodes::SqlLiteral"
      send(:"#{type}=", [name, value])
      # instance_variable_get(:"@#{type.sub(/s*$/,'s')}")[name&.to_sym] = value
    end
    @quotes.update quotes
    self
  end

  def to_sql
    mixin!
    raise Error.new(self, errors) if errors?
    return Arel.sql @sql if defined? Arel
    @sql
  end

  def returning(returning)
    @returning = returning
    self
  end

  def result(*binds, prepare: false, async: false, &block)
    sql = to_sql
    if binds.present? and sql.scan(/(?<=\$)\d+/).map(&:to_i).max != binds.length
      raise ArgumentError, "Wrong number of binds"
    end

    add_returning(sql) if @returning.present? and not sql.match? /\bRETURNING\b/i
    if @returning
      process_returning _exec_query(sql, binds, prepare: false)
    else
      result = _exec(sql, binds, prepare: false)
      result = result.map(&block).compact if block_given?
      result
    end

  rescue => exc
    STDERR.puts exc.inspect, self.inspect
    raise exc
  end

  private def add_returning(sql)
    quote = -> columns do
      if columns.respond_to? :column_names
        c = columns.column_names.map{ "#{columns.table_name}.#{_1}" }
      else
        c = columns
      end
      " RETURNING #{c.join(",")}"
    end
    case @returning
    when Array, String, Symbol
      sql << quote.call(Array(@returning))
    when ActiveRecord::Relation
      sql << (@returning.select_values.present? ? quote.call(@returning.select_values) : quote.call(@returning.klass))
    when Class
      if @returning.respond_to? :column_names
        sql << quote.call(@returning)
      end
    end

  end

  private def process_returning(result)
    case @returning
    when NilClass
      result
    when ActiveRecord::Relation
      @returning.send(:instantiate_records, result)
    when Proc
      @returning.call result
    when Class
      if @returning < ActiveRecord::Base
        @returning.send(:relation).send(:instantiate_records, result)
      elsif @returning.respond_to? :instantiate_records
        @returning.instantiate_records(result)
      else
        result.map { @returning.new _1 }
      end
    else
      raise "Returning not defined"
    end
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
      _exec(sql, record, prepare: false)
    end
  end

  def reset
    @sql = @original
  end

  def errors
    @quotes.to_h do |k, v|
      r = @resolved[k]
      next [nil, nil] if r.nil? or not r.is_a?(Exception)
      [k, { @quotes[k].inspect => v.inspect, exc: r, backtrace: r.backtrace }]
    end.compact
  end

  def errors?
    @resolved.any? { _2.is_a? Exception }
  end

  MIXIN_RE = /(%\{?([a-z][a-z0-9_]*)}|%([a-z][a-z0-9_]*)\b)/im

  def key_matches
    @sql.scan(MIXIN_RE).map do |full, *key|
      key = key.compact[0]
      has_quote = @quotes.key?(key.to_sym) || key.match?(/(table|columns)$/)
      [full, key, has_quote]
    end
  end

  def mixin!
    unresolved = Set.new(key_matches.map(&:second))
    last_unresolved = Set.new
    loop do
      s = StringScanner.new(@sql)
      sql = ""
      key_matches.each do |key_match, key, has_quote|
        s.scan_until(/(.*?)#{key_match}(#{CASTS}?)/im)
        matched, pre, cast = s.matched, s[1], s[2]
        # if m = key.match(/^bind(\d+)?/im)
        #   if m[1].present?
        #     bind_num = m[1].to_i
        #     @binds[bind_num - 1] ||= cast
        #     raise "bind #{bind_num} already set to #{@binds[bind_num - 1]}" unless @binds[bind_num - 1] == cast
        #   else
        #     @binds << cast
        #     bind_num = @binds.length
        #   end
        #
        #   matched = "#{pre}$#{bind_num}#{"::#{cast}" if cast.present?}#{post}"
        # els
        if has_quote
          quoted = quoter(key, cast)
          unresolved.delete key
          if (i = quoted.scan MIXIN_RE).present?
            unresolved += i.map(&:last)
          end
          matched = "#{pre}#{quoted}#{cast}"
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

  def quoter(key, cast)
    quoter = @resolved[key.to_sym] = Quoter.new(self, key, cast, @quotes[key.to_sym])
    quoter.to_sql
  rescue TypeError => exc
    @resolved[key.to_sym] = exc
    raise exc
  end

  extend Quoting

  class Raw < String
    def self.sql(v)
      if v.class == self
        v
      elsif v.respond_to? :to_sql
        new v.to_sql
      else
        new v
      end
    end
  end

  def self.test(which = :all)
    require __dir__ + "/quote_sql/test.rb"
    case which
    when :all
      Test.new.all
    when :datatype
      Test.new.datatype
    else
      Test.new.run(which)
    end
  end
end

def QuoteSQL(sql, **options)
  rv = QuoteSql.new(sql)
  options.any? ? rv.quote(**options) : rv
end

QuoteSql.include QuoteSql::Formater

