class QuoteSql
  class Quoter
    def initialize(qsql, key, cast, quotable)
      @qsql = qsql
      @key, @cast, @quotable = key, cast, quotable
      @name = key.sub(/_[^_]+$/, '') if key["_"]
    end

    attr_reader :key, :quotable, :name, :cast

    def quotes
      @qsql.quotes
    end

    def table(name = nil)
      @qsql.table(name || self.name)
    end

    def ident_table(i = nil)
      Raw.sql(Array(self.table(name)).compact[0..i].map do |table|
        if table.respond_to? :table_name
          QuoteSql.quote_column_name table.table_name
        elsif table.present?
          QuoteSql.quote_column_name table
        end
      end.join(","))
    end

    def columns(name = nil)
      @qsql.columns(name || self.name)
    end

    def casts(name = nil)
      @qsql.casts(name || self.name)
    end

    def ident_columns(name = nil)
      item = columns(name || self.name)
      unless item
        unless item = casts(name || self.name)&.keys
          if (table = self.table(name || self.name))&.respond_to? :column_names
            item = table.column_names
          else
            raise ArgumntError, "No columns, casts or table given for #{name}" unless table&.respond_to? :column_names
          end
        end
      end
      if item.is_a?(Array)
        if item.all? { _1.respond_to?(:name) }
          item = item.map(&:name)
        end
      end
      _ident(item)
    end

    def _quote_ident(item)
      Raw.sql case item.class.to_s
              when "QuoteSql::Raw", "Arel::Nodes::SqlLiteral" then item
              when "Hash" then json_hash_ident(item)
              when "Array" then json_array_ident(item)
              when "Proc" then item.call(self)
              when "Integer" then "$#{item}"
              when "Symbol" then [ident_table(0).presence, _quote_ident(item.to_s)].compact.join(".")
              when "String" then item.scan(/(?:^|")?([^."]+)/).flatten.map { QuoteSql.quote_column_name _1 }.join(".")
              else raise ArgumentError, "just Hash, Array, Arel::Nodes::SqlLiteral, QuoteSql::Raw, String, Symbol, Proc, Integer, or responding to #to_sql"
              end
    end

    def _ident(item = @quotable)
      return Raw.sql(item) if item.respond_to?(:to_sql)
      rv = case item.class.to_s
           when "Array"
             item.map { _1.is_a?(Hash) ? _ident(_1) : _quote_ident(_1) }.join(",")
           when "Hash"
             item.map { "#{_quote_ident(_2)} AS \"#{_1}\"" }.join(",")
           else
             _quote_ident(item)
             # _quote_column_name(item)
           end
      Raw.sql rv
    end

    def to_sql
      return @quotable.call(self) if @quotable.is_a? Proc
      case key.to_s
      when /(?:^|(.*)_)table$/i
        ident_table
      when /(?:^|(.*)_)columns$/i
        ident_columns
      when /(?:^|(.*)_)(ident)$/i
        _ident
      when /(?:^|(.*)_)constraints?$/i
        quotable
      when /(?:^|(.*)_)(raw|sql)$/i
        quotable
      when /^(.+)_json$/i
        data_json
      when /^(.+)_values$/i
        data_values
      when /values$/i
        insert_values
      else
        quote
      end
    end

    ###############

    private def value(values)
      # case values.class.to_s
      # when "QuoteSql::Raw", "Arel::Nodes::SqlLiteral" then rv = values
      # when "Array"
      # when "Hash"
      #   columns = self.columns(name)&.flat_map { _1.is_a?(Hash) ? _1.values : _1 }
      #   if columns.nil?
      #     values = values.values
      #   elsif columns.all? { _1.is_a? Symbol }
      #     raise ArgumentError, "Columns just Symbols"
      #   else
      #     values = columns.map do |column|
      #       if values.key?(column&.to_sym) or !defaults
      #         values[column.to_sym]
      #       elsif column[/^(created|updated)_at$/]
      #         :current_timestamp
      #       else
      #         :default
      #       end
      #     end
      #   end
      # else
      #   raise ArgumentError, "value just Array, Hash, QuoteSql::Raw, Arel::Nodes::SqlLiteral"
      # end

      rv ||= values.map do |i|
        case i
        when :default, :current_timestamp
          next i.to_s.upcase
        when Hash, Array
          i = i.to_json
        end
        _quote(i)
      end
      Raw.sql "(#{rv.join(",")})"
    end

    def data_json(item = @quotable)
      casts = self.casts(name)
      columns = self.columns(name) || casts&.keys
      column_cast = columns&.map { "#{QuoteSql.quote_column_name(_1)} #{casts&.dig(_1) || "TEXT"}" }
      if item.is_a? Integer
        rv = "$#{item}"
      else
        item = [item].flatten.compact.as_json.map { _1.slice(*columns.map(&:to_s)) }
        rv = "'#{item.to_json.gsub(/'/, "''")}'"
      end
      Raw.sql "json_to_recordset(#{rv}) AS #{QuoteSql.quote_column_name name}(#{column_cast.join(',')})"
    end

    def data_values(item = @quotable)
      item = Array(item).compact
      column_names = columns(name)
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
        column_names ||= (1..length).map { "column#{_1}" }
        raise ArgumentError, "#{name}_columns and value lengths need to be the same" if column_names.length != length
        values = item.map { value(_1) }
      else
        raise ArgumentError, "Either all type Hash or Array"
      end
      if types.present?
        value = values[0][1..-2].split(/\s*,\s*/)
        types.each_with_index { value[_2] << _1 || "" }
        values[0] = "(" + value.join(",") + ")"
      end
      # values[0] { _1 << types[_1] || ""}
      Raw.sql "(VALUES #{values.join(",")}) AS #{_ident name} (#{_ident column_names})"
    end

    def insert_values(item = @quotable)
      case item
      when Arel::Nodes::SqlLiteral
        item = Raw.sql("(#{item})") unless item[/^\s*\(/] and item[/\)\s*$/]
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
          Raw.sql "(#{_ident column_names}) VALUES #{values.join(",")}"
        else
          Raw.sql "VALUES #{values.join(",")}"
        end
      when Hash
        value([item])
      end
    end

    def json?(cast = self.cast)
      cast.to_s[/jsonb?$/i]
    end

    private def _quote(item = @quotable)
      Raw.sql QuoteSql.quote(item)
    end

    private def _quote_column_name(name)
      Raw.sql name.scan(/(?:^|")?([^."]+)/).map { QuoteSql.quote_column_name _1 }.join(".")
    end

    private def _quote_array(items)
      rv = items.map do |i|
        if i.is_a?(Array)
          _quote_array(i)
        elsif self.cast[/jsonb?/i]
          _quote(i.to_json)
        else
          quote(i)
        end
      end
      "[#{rv.join(",")}]"
    end

    def quote_hash(item)
      item.compact! if item.delete(nil) == false
      case self.cast
      when /hstore/i
        _quote(item.map { "#{_1}=>#{_2.nil? ? 'NULL' : _2}"}.join(","))
      when NilClass,""
        "#{_quote(item.to_json)}::JSONB"
      when /jsonb?/i
        _quote(item.to_json)
      end
    end

    def quote(item = @quotable, cast = nil)
      Raw.sql case item.class.to_s
              when "Arel::Nodes::SqlLiteral", "QuoteSql::Raw"
                item
              when "Array"
                if json? or self.cast.blank?
                  rv = _quote(item.to_json)
                  self.cast.present? ? rv : "#{rv}::JSONB"
                else
                  "ARRAY#{_quote_array(item)}"
                end
              when "Hash"
                quote_hash(item)
              else
                if item.respond_to? :to_sql
                  item.to_sql
                elsif json?
                  _quote(item.to_json)
                else
                  _quote(item)
                end
              end
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
      _ident(item)
    end

    def json_array_values(h)
      Raw.sql "'#{h.to_json.gsub(/'/, "''")}'::JSONB"
    end

    def json_hash_values(h)
      compact = h.delete(nil) == false
      rv = json_array_values(h)
      Raw.sql(compact ? "jsonb_strip_nulls(#{rv})" : rv)
    end

    def json_hash_ident(h)
      compact = h.delete(nil) == false
      rv = "jsonb_build_object(" + h.map { "'#{_1.to_s.gsub(/'/, "''")}', #{_ident(_2)}" }.join(",") + ")"
      Raw.sql(compact ? "jsonb_strip_nulls(#{rv})" : rv)
    end

    def json_array_ident(h)
      Raw.sql "jsonb_build_array(#{h.map { _ident(_2) }.join(",")})"
    end

    # def table(item = @quotable)
    #   @qsql.table_name ||= if item.respond_to?(:table_name)
    #                          item = item.table_name
    #                        elsif item.class.respond_to?(:table_name)
    #                          item = item.class.table_name
    #                        end
    #   table_name(item || @qsql.table_name)
    # end
    #
    # def table_name(item = @quotable)
    #   case item
    #   when Array
    #     item.map do |item|
    #       item.is_a?(Hash) ? table_name(item) : _quote_column_name(item)
    #     end.join(",")
    #   when Hash
    #     raise NotImplementedError, "table name is a Hash"
    #     # perhaps as ...
    #   else
    #     _quote_column_name(item)
    #   end
    # end
  end
end