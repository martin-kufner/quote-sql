Dir.glob(__FILE__.sub(/\.rb$/, "/*.rb")).each { require(_1) unless _1[/(deprecated|test)\.rb$/] }

# Tool to build and run SQL queries easier
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

    @tables = {}
    @columns = {}
    @casts = {}
  end

  attr_reader :sql, :quotes, :original, :binds, :tables, :columns

  def table(name = nil)
    @tables[name&.to_sym].dup
  end

  def columns(name = nil)
    @columns[name&.to_sym].dup
  end

  def casts(name = nil)
    unless rv = @casts[name&.to_sym]
      table = table(name) or return
      return unless table.respond_to? :columns
      rv = table.columns.to_h { [_1.name.to_sym, _1.sql_type] }
    end
    rv
  end

  # Add quotes keys are symbolized
  def quote(quotes = {})
    re = /(?:^|(.*)_)(table|columns|casts)$/i
    quotes.keys.grep(re).each do |quote|
      _, name, type = quote.to_s.match(re)&.to_a
      value = quotes.delete quote
      value = Raw.sql(value) if value.class.to_s == "Arel::Nodes::SqlLiteral"
      instance_variable_get(:"@#{type.sub(/s*$/,'s')}")[name&.to_sym] = value
    end
    @quotes.update quotes.transform_keys(&:to_sym)
    self
  end

  def to_sql
    mixin!
    raise Error.new(self, errors) if errors?
    return Arel.sql @sql if defined? Arel
    @sql
  end

  def result(*binds, prepare: false, async: false)
    sql = to_sql
    if binds.present? and sql.scan(/(?<=\$)\d+/).map(&:to_i).max != binds.length
      raise ArgumentError, "Wrong number of binds"
    end
    _exec(sql, binds, prepare: false, async: false)
  rescue => exc
    STDERR.puts exc.inspect, self.inspect
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
      if m = key.match(/^(.+)#{CASTS}/i)
        _, key, cast = m.to_a
      end
      has_quote = @quotes.key?(key.to_sym) || key.match?(/(table|columns)$/)
      [full, key, cast, has_quote]
    end
  end

  def mixin!
    unresolved = Set.new(key_matches.map(&:second))
    last_unresolved = Set.new
    loop do
      s = StringScanner.new(@sql)
      sql = ""
      key_matches.each do |key_match, key, cast, has_quote|
        s.scan_until(/(.*?)#{key_match}([a-z0-9_]*)/im)
        matched, pre, post = s.matched, s[1], s[2]
        if m = key.match(/^bind(\d+)?/im)
          if m[1].present?
            bind_num = m[1].to_i
            @binds[bind_num - 1] ||= cast
            raise "bind #{bind_num} already set to #{@binds[bind_num - 1]}" unless @binds[bind_num - 1] == cast
          else
            @binds << cast
            bind_num = @binds.length
          end

          matched = "#{pre}$#{bind_num}#{"::#{cast}" if cast.present?}#{post}"
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
    if which == :all
      Test.new.all
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

class Array
  def depth
    select { _1.is_a?(Array) }.map { _1.depth.to_i + 1 }.max || 1
  end
end

