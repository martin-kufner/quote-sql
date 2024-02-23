class QuoteSql
  module Extension
    def self.included(other)
      other.include QuoteSql::Formater
    end

    def quote_sql(**)
      QuoteSql.new(self).quote(**)
    end

    alias qsql quote_sql
  end
end

