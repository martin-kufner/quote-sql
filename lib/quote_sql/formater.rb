require 'niceql'
class QuoteSql
  module Formater
    PG_FORMAT_BIN = `which pg_format`.chomp.presence

    def dsql
      puts to_formatted_sql
      nil
    end

    def to_formatted_sql
      sql = respond_to?(:to_sql) ? to_sql : to_s
      Niceql::Prettifier.prettify_sql(sql.gsub(/(?<=[^%])%(?=\S)/, "%%"))

      # IO.popen(PG_FORMAT_BIN, "r+", err: "/dev/null") do |f|
      #   f.write(sql)
      #   f.close_write
      #   f.read
      # end

    end

    alias to_sqf to_formatted_sql
  end
end