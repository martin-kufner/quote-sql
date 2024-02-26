class QuoteSql
  class Error < ::RuntimeError
    def initialize(quote_sql, errors)
      @object = quote_sql
      @errors = errors
    end

    attr_reader :object, :errors

    def original
      @object.original.dsql
    end

    def sql
      @object.sql.dsql
    end

    def tables
      @object.tables.inspect
    end

    def columns
      @object.columns.inspect
    end

    def quotes
      @object.quotes.inspect
    end

    def message

      errors = @object.errors.map do |quote, error|
        error => {exc:, backtrace:, **transformations}

        "#{quote}: #{exc.class} #{exc.message} #{transformations.inspect}\n#{backtrace.join("\n")}"
      end
      <<~ERROR
                Original: #{original}
                Tables:  
                Quotes: #{quotes} 
                Processed: #{sql}
        #{errors.join("\n\n")}
        #{'*' * 40}
      ERROR
    end
  end
end