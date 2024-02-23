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
          conn.quote(name)
        end
      end

      def conn
        self.class.conn
      end

      def _exec_query(sql, binds = [], prepare: false, async: false)
        conn.exec_query(sql, "SQL", binds, prepare:, async:)
      end

      def _exec(sql, binds = [], prepare: false, async: false)
        options = { prepare:, async: }
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