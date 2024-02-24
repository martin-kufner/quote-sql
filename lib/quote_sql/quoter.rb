class QuoteSql
  class Quoter
    def initialize(qsql, key, quotable)
      @qsql = qsql
      @key, @quotable = key, quotable
    end

    def quotes
      @qsql.quotes
    end

    attr_reader :key, :quotable

    def name
      @key.sub(/_[^_]+$/, '')
    end

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
      when /^(.+)_values$/i
        data_values
      when /values$/i
        insert_values
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

    def data_values(item = @quotable)
      item = Array(item).compact
      column_names = @qsql.quotes[:"#{name}_columns"].dup
      if column_names.is_a? Hash
        types = column_names.values.map { "::#{_1.upcase}" if _1 }
        column_names = column_names.keys
      end
      if item.all? { _1.is_a?(Hash) }
        column_names ||= item.flat_map { _1.keys.sort }.uniq
        item.map! { _1.fetch_values(*column_names) {} }
      end
      if item.all? { _1.is_a?(Array) }
        length, overflow = item.map { _1.length }.uniq
        raise ArgumentError, "all values need to have the same length" if overflow
        column_names ||= (1..length).map{"column#{_1}"}
        raise ArgumentError, "#{name}_columns and value lengths need to be the same" if column_names.length != length
        values = item.map { value(_1) }
      else
        raise ArgumentError, "Either all type Hash or Array"
      end
      if types.present?
        value = values[0][1..-2].split(/\s*,\s*/)
        types.each_with_index { value[_2] << _1 || ""}
        values[0] = "(" + value.join(",") + ")"
      end
      # values[0] { _1 << types[_1] || ""}
      "(VALUES #{values.join(",")}) AS #{ident_name name} (#{ident_name column_names})"
    end


    def insert_values(item = @quotable)
      case item
      when Arel::Nodes::SqlLiteral
        item = Arel.sql("(#{item})") unless item[/^\s*\(/] and item[/\)\s*$/]
        return item
      when Array
        item.compact!
        column_names = (@qsql.quotes[:columns] || @qsql.quotes[:column_names]).dup
        types = []
        if column_names.is_a? Hash
          types = column_names.values.map { "::#{_1.upcase}" if _1 }
          column_names = column_names.keys
        elsif column_names.is_a? Array
          column_names = column_names.map do |column|
            types << column.respond_to?(:sql_type) ? "::#{column.sql_type}" : nil
            column.respond_to?(:name) ? column.name : column
          end
        end

        if item.all? { _1.is_a?(Hash) }
          column_names ||= item.flat_map { _1.keys.sort }.uniq
          item.map! { _1.fetch_values(*column_names) {} }
        end

        if item.all? { _1.is_a?(Array) }
          length, overflow = item.map { _1.length }.uniq
          raise ArgumentError, "all values need to have the same length" if overflow
          raise ArgumentError, "#{name}_columns and value lengths need to be the same" if column_names and column_names.length != length
          values = item.map { value(_1) }
        else
          raise ArgumentError, "Either all type Hash or Array"
        end
        if column_names.present?
          "(#{ident_name column_names}) VALUES #{values.join(",")}"
        else
          "VALUES #{values.join(",")}"
        end
      when Hash
        value([item])
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
        if item.all?{ _1.respond_to?(:name) }
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