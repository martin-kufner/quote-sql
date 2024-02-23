class QuoteSql
  module Deprecated
    private def conn
      ApplicationRecord.connection
    end

    private def quote_sql_values(sub, casts)
      sub.map do |s|
        casts.map do |k, column|
          column.transform_keys(&:to_sym) => { sql_type:, default:, array: }
          value = s.key?(k) ? s[k] : s[k.to_sym]
          if value.nil?
            value = default
          else
            value = value.to_json if sql_type[/^json/]
          end
          "#{conn.quote(value)}::#{sql_type}"
        end.join(",")
      end
    end

    def quote_sql(**options)
      loop do
        # keys = []
        break unless gsub!(%r{(?<=^|\W)[:$](#{options.keys.join("|")})(?=\W|$)}) do |m|
          key = m[1..].to_sym
          # keys << key
          next m unless options.key? key
          sub = options[key]
          case sub
          when Arel::Nodes::SqlLiteral
            next sub
          when NilClass
            next "NULL"
          when TrueClass, FalseClass
            next sub.to_s.upcase
          when Time
            sub = sub.strftime("%Y-%m-%d %H:%M:%S.%3N%z")
          end
          if sub.respond_to? :to_sql
            next sub.to_sql
          end
          case m
          when /^:(.+)_(FROM_CLAUSE)$/ # prefix (column,...) AS ( VALUES (data::CAST, ...), ...)
            name = conn.quote_column_name($1)
            casts = sub.shift.transform_keys(&:to_s)
            rv = quote_sql_values(sub, casts)
            column_names = casts.map { conn.quote_column_name(_2.key?(:as) ? _2[:as] : _1) }
            next "(VALUES \n(#{rv.join("),\n(")})\n ) #{name} (#{column_names.join(",") })"

          when /^:(.+)_(as_select)$/i # prefix (column,...) AS ( VALUES (data::CAST, ...), ...)
            name = conn.quote_column_name($1)
            casts = sub.shift.transform_keys(&:to_s)
            rv = quote_sql_values(sub, casts)
            next "SELECT * FROM (VALUES \n(#{rv.join("),\n(")})\n ) #{name} (#{casts.keys.map { conn.quote_column_name(_1) }.join(",") })"
          when /^:(.+)_(as_values)$/i # prefix (column,...) AS ( VALUES (data::CAST, ...), ...)
            name = conn.quote_column_name($1)
            casts = sub.shift.transform_keys(&:to_s)
            rv = quote_sql_values(sub, casts)
            next "#{name} (#{casts.keys.map { conn.quote_column_name(_1) }.join(",") }) AS ( VALUES \n(#{rv.join("),\n(")})\n )"
          when /^:(.+)_(values)$/i
            casts = sub.shift.transform_keys(&:to_sym)
            rv = quote_sql_values(sub, casts)
            next "VALUES \n(#{rv.join("),\n(")})\n"
          when /_(LIST)$/i
            next sub.map { conn.quote _1 }.join(",")
          when /_(args)$/i
            next sub.join(',')
          when /_(raw|sql)$/i
            next sub
          when /_(ident|column)$/i, /table_name$/, /_?columns?$/, /column_names$/
            if sub.is_a? Array
              next sub.map do
                _1[/^"[^"]+"\."[^"]+"$/] ? _1 : conn.quote_column_name(_1)
              end.join(',')
            else
              next conn.quote_column_name(sub)
            end
          when /(?<=_)jsonb?$/i
            next conn.quote(sub.to_json) + "::#{$MATCH}"
          when /(?<=_)(uuid|int|text)$/i
            cast = "::#{$MATCH}"
          end
          case sub
          when Regexp
            sub.to_postgres
          when Array
            dims = 1 # todo more dimensional Arrays
            dive = ->(ary) do
              ary.map { |s| conn.quote s }.join(',')
            end
            sub = "[#{dive.call sub}]"
            cast += "[]" * dims if cast.present?
            "ARRAY#{sub}#{cast}"
          else
            "#{conn.quote(sub)}#{cast}"
          end
        end
        # break if options.except!(*keys).blank?
      end
      Arel.sql self
    end

    def exec
      result = conn.exec_query(self)
      columns = result.columns.map(&:to_sym)
      result.cast_values.map do |row|
        row = [row] unless row.is_a? Array
        [columns, row].transpose.to_h
      end
    end

    def quote_exec(**)
      quote_sql(**).exec
    end

    module Dsql

      def dsql
        IO.popen(PG_FORMAT_BIN, "r+", err: "/dev/null") do |f|
          f.write self
          f.close_write
          puts f.read
        end
        self
      rescue
        self
      end
    end

    include Dsql

    module String
      def self.included(other)
        other.include Dsql
      end

      def quote_sql(**)
        Arel.sql(self).quote_sql(**)
      end
    end

    module Relation
      def quote_sql(**)
        Arel.sql(to_sql).quote_sql(**)
      end

      def dsql
        to_sql.dsql
        self
      end

      def result
        result = ApplicationRecord.connection.exec_query(to_sql)
        columns = result.columns.map(&:to_sym)
        result.cast_values.map do |row|
          [columns, Array(row)].transpose.to_h
        end
      end
    end
  end
end