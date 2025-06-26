class QuoteSql
  module Connector
    module ActiveRecordBase
      module ClassMethods
        def conn
          ::ActiveRecord::Base.connection
        end

        def quote_column_name(name)
          conn.quote_column_name(name)
        end

        def quote(name)
          if name.is_a? Array
            "ARRAY[#{name.map{conn.quote(_1)}.join(",")}]"
          elsif name.is_a? Hash
            conn.quote(name.to_json)
          else
            conn.quote(name)
          end
        end
      end

      def conn
        @connection || self.class.conn
      end

      def _exec_query(sql, binds = [], **options)
        conn.exec_query(sql, "SQL", binds, **options)
      end

      def _exec(sql, binds = [], **options)
        result = _exec_query(sql, binds, **options)
        columns = result.columns.map(&:to_sym)
        result.cast_values.map do |row|
          row = [row] unless row.is_a? Array
          [columns, row].transpose.to_h
        end
      end
    end
  end
end