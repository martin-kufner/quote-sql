class QuoteSql
  module Extension
    def self.included(other)
      other.include QuoteSql::Formater
    end

    def quote_sql(connection=nil, **)
      QuoteSql.new(self, connection:).quote(**)
    end

    alias qsql quote_sql
  end
end

