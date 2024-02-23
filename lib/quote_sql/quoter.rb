class QuoteSql
  class Quoter
    def initialize(qsql, key, quotable)
      @qsql = qsql
      @key, @quotable = key, quotable
    end

    attr_reader :key, :quotable

    def to_sql
      return @quotable.call(self) if @quotable.is_a? Proc
      case key.to_s
      when /(?:^|(.*)_)table$/i
        table
      when /(?:^|(.*)_)columns?$/i
        columns
      when /(?:^|(.*)_)(table_name?s?)$/i
        table_name
      when /(?:^|(.*)_)(column_name?s?)$/i
        ident_name
      when /(?:^|(.*)_)(ident|args)$/i
        ident_name
      when /(?:^|(.*)_)constraints?$/i
        quotable.to_s
      when /(?:^|(.*)_)(raw|sql)$/i
        quotable.to_s
      when /(?:^|(.*)_)(values?)$/i
        values
      else
        quote
      end
    end

    private def value(ary)
      column_names = @qsql.column_names
      if ary.is_a?(Hash) and column_names.present?
        ary = @qsql.column_names.map do |column_name|
          if ary.key? column_name&.to_sym
            ary[column_name.to_sym]
          elsif column_name[/^(created|updated)_at$/]
            :current_timestamp
          else
            :default
          end
        end
      end
      "(" + ary.map do |i|
        case i
        when :default, :current_timestamp
          next i.to_s.upcase
        when Hash, Array
          i = i.to_json
        end
        _quote(i)
      end.join(",") + ")"

    end

    def values(item = @quotable)
      case item
      when Arel::Nodes::SqlLiteral
        item = Arel.sql("(#{item})") unless item[/^\s*\(/] and item[/\)\s*$/]
        return item
      when Array

        differences = item.map { _1.is_a?(Array) && _1.length }.uniq
        if differences.length == 1
          item.compact.map { value(_1) }.join(", ")
        else
          value([item])
        end
      when Hash
        value([item])
      else
        return item.to_sql if item.respond_to? :to_sql
        "(" + _quote(item) + ")"
      end
    end

    def cast
      if m = key.to_s[CASTS]
        m[2..].sub(CASTS) { _1.tr("_", " ") }
      end
    end

    def json?
      !!key[/(^|_)(jsonb?)$/]
    end

    private def _quote(item = @quotable, cast = self.cast)
      rv = QuoteSql.quote(item)
      if cast
        rv << "::#{cast}"
        rv << "[]" * rv.depth if rv[/^ARRAY/]
      end
      rv
    end

    private def _quote_column_name(name, column = nil)
      name, column = name.to_s.split(".") if column.nil?
      rv = QuoteSql.quote_column_name(name)
      return rv unless column.present?
      rv + "." + QuoteSql.quote_column_name(column)
    end

    def quote(item = @quotable)
      case item
      when Arel::Nodes::SqlLiteral
        return item
      when Array
        return _quote(item.to_json) if json?
        _quote(item)
      when Hash
        return _quote(item.to_json) if json?
        item.map do |as, item|
          "#{_quote(item)} AS #{as}"
        end.join(",")
      else
        return item.to_sql if item.respond_to? :to_sql
        _quote(item)
      end
    end

    def columns(item = @quotable)
      if item.respond_to?(:column_names)
        item = item.column_names
      elsif item.class.respond_to?(:column_names)
        item = item.class.column_names
      elsif item.is_a?(Array)
        if item[0].respond_to?(:name)
          item = item.map(&:name)
        end
      end
      @qsql.column_names ||= item
      ident_name(item)
    end

    def column_names(item = @quotable)
      if item.respond_to?(:column_names)
        item = item.column_names
      elsif item.class.respond_to?(:column_names)
        item = item.class.column_names
      elsif item.is_a?(Array) and item[0].respond_to?(:name)
        item = item.map(&:name)
      end
      @qsql.column_names ||= item
      ident_name(item)
    end

    def json_build_object(h)
      compact = h.delete(nil) == false
      rv = "jsonb_build_object(" + h.map { "'#{_1}',#{_2}" }.join(",") + ")"
      return rv unless compact
      "jsonb_strip_nulls(#{rv})"
    end

    def ident_name(item = @quotable)
      case item
      when Array
        item.map do |item|
          case item
          when Hash
            ident_name(item)
          when String, Symbol
            _quote_column_name(item)
          when Proc
            item.call(self)
          end
        end.join(",")
      when Hash
        item.map do |k,v|
          case v
          when Symbol
            _quote_column_name(k, v)
          when String
            "#{v} AS #{k}"
          when Proc
            item.call(self)
          when Hash
            "#{json_build_object(v)} AS #{k}"
          else
            raise ArgumentError
          end
        end.join(",")
      else
        _quote_column_name(item)
      end
    end

    def table(item = @quotable)
      @qsql.table_name ||= if item.respond_to?(:table_name)
                             item = item.table_name
                           elsif item.class.respond_to?(:table_name)
                             item = item.class.table_name
                           end
      table_name(item || @qsql.table_name)
    end

    def table_name(item = @quotable)
      case item
      when Array
        item.map do |item|
          item.is_a?(Hash) ? table_name(item) : _quote_column_name(item)
        end.join(",")
      when Hash
        raise NotImplementedError, "table name is a Hash"
        # perhaps as ...
      else
        _quote_column_name(item)
      end
    end
  end
end