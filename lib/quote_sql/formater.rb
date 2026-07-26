# require 'niceql'
require 'sql_beautifier'
# require 'anbt-sql-formatter/formatter'
require 'rouge'


class QuoteSql
  module Formater
    def dsql
      Rails.logger.info to_formatted_sql
      nil
    end

    # private def niceql(sql)
    #   Niceql::Prettifier.prettify_sql(sql)
    # end
    #
    private def sql_beautifier(sql)
      formatted = SqlBeautifier.call(
        sql,
                         keyword_case: :upper,
      clause_spacing_mode: :compact,
        table_name_format: :lowercase,
        alias_strategy: :none,
      ).gsub(/\n+/, "\n")
      formatter = Rouge::Formatters::Terminal256.new
      lexer = Rouge::Lexers::SQL.new
      formatter.format(lexer.lex(formatted))
    end

    # private def anbt_sql(sql)
    #   rule = AnbtSql::Rule.new
    #   rule.keyword = AnbtSql::Rule::KEYWORD_UPPER_CASE
    #   rule.indent_string = "  "
    #   rule.space_after_comma = true
    #   rule.function_names << "COALESCE"
    #   formatted = AnbtSql::Formatter.new(rule).format(sql)
    #
    #   # 2. Einfärben für das Terminal
    #   formatter = Rouge::Formatters::Terminal256.new
    #   lexer = Rouge::Lexers::SQL.new
    #   formatter.format(lexer.lex(formatted))
    # end

    def to_formatted_sql
      sql = respond_to?(:to_sql) ? to_sql : to_s
      sql = sql.gsub(/(?<=[^%])%(?=\S)/, "%%")
      # niceql(sql)

      sql_beautifier(sql)
      # anbt_sql(sql)
      # IO.popen(PG_FORMAT_BIN, "r+", err: "/dev/null") do |f|
      #   f.write(sql)
      #   f.close_write
      #   f.read
      # end

    end

    alias to_sqf to_formatted_sql
  end
end