module QuoteSql::Test
  def self.all
    @success = []
    @fail = []
    methods(false).grep(/^test_/).each do |name|
      run(name, true)
    end
    @success.each { STDOUT.puts(*_1, nil) }
    @fail.each { STDOUT.puts(*_1, nil) }
    puts
  end

  def self.run(name, all)
    name = name.to_s.sub(/^test_/, "")
    @expected = nil
    @test = send("test_#{name}")

    if sql.gsub(/\s+/, "")&.downcase&.strip == expected&.gsub(/\s+/, "")&.downcase&.strip
      rv = [name, @test.original, @test.quotes.inspect, "✅ #{expected}"]
      @success << rv if @success
    else
      rv = [name, @test.inspect, sql, "❌ #{expected}"]
      @fail << rv if @fail
    end
    STDOUT.puts rv unless @fail or @success
  end

  def self.expected(v = nil)
    @expected ||= v
  end

  def self.sql
    @test.to_sql
  end

  class PseudoActiveRecord
    def self.table_name
      "pseudo_active_records"
    end

    def self.column_names
      %w(id column1 column2)
    end

    def to_qsl
      "SELECT * FROM #{self.class.table_name}"
    end
  end

  class << self
    def test_columns_and_table_name_simple
      expected %(SELECT "a","b"."c" FROM "my_table")
      QuoteSql.new("SELECT %columns FROM %table_name").quote(
        columns: [:a, b: :c],
        table_name: "my_table"
      )
    end

    def test_columns_and_table_name_complex
      expected %(SELECT "a","b"."c" FROM "table1","table2")
      QuoteSql.new("SELECT %columns FROM %table_names").quote(
        columns: [:a, b: :c],
        table_names: ["table1", "table2"]
      )
    end

    def test_recursive_injects
      expected %(SELECT TRUE FROM "table1")
      QuoteSql.new("SELECT %raw FROM %table_names").quote(
        raw: "%recurse1_raw",
        recurse1_raw: "%recurse2",
        recurse2: true,
        table_names: "table1"
      )
    end

    def test_values
      expected <<~SQL
        SELECT 'a text', 123, 'text' AS abc FROM "my_table"
      SQL
      QuoteSql.new("SELECT %text, %{number}, %aliased_with_hash FROM %table_name").quote(
        text: "a text",
        number: 123,
        aliased_with_hash: {
          abc: "text"
        },
        table_name: "my_table"
      )
    end

    def test_binds
      expected <<~SQL
                SELECT $1, $2, $1 AS get_bind_1_again FROM "my_table"
         SQL
          QuoteSql.new("SELECT %bind, %bind__uuid, %bind1 AS get_bind_1_again FROM %table_name").quote(
            table_name: "my_table"
          )
        end

        def test_from_values_array
          expected <<~SQL
                SELECT * FROM (VALUES ('a',1,TRUE,NULL)) AS "x" ("column1","column2","column3","column4")
      SQL
      "SELECT * FROM %x_values".quote_sql(x_values: [['a', 1, true, nil]])
    end

    def test_from_values_hash_no_columns
      expected <<~SQL
        SELECT * FROM (VALUES ('a', 1, true, NULL), ('a', 1, true, NULL), (NULL, 1, NULL, 2)) AS "y" ("a", "b", "c", "d")
      SQL
      "SELECT * FROM %y_values".quote_sql(y_values: [
        { a: 'a', b: 1, c: true, d: nil },
        { d: nil, a: 'a', c: true, b: 1 },
        { d: 2, b: 1 }
      ])
    end

    def test_from_values_hash_with_columns
      expected <<~SQL
        SELECT * FROM (VALUES (NULL, true, 1, 'a')) AS "x" ("d","c","b","a")
      SQL
      "SELECT * FROM %x_values".quote_sql(x_columns: %i[d c b a], x_values: [{ a: 'a', b: 1, c: true, d: nil }])
    end

    def test_from_values_hash_with_type_columns
      expected <<~SQL
        SELECT * FROM (VALUES ('a'::TEXT, 1::INTEGER, true::BOOLEAN, NULL::FLOAT), ('a', 1, true, NULL), (NULL, 1, NULL, 2)) AS "x" ("a", "b", "c", "d")
      SQL
      "SELECT * FROM %x_values".quote_sql(
        x_columns: {
          a: "text",
          b: "integer",
          c: "boolean",
          d: "float"
        },
        x_values: [
          { a: 'a', b: 1, c: true, d: nil },
          { d: nil, a: 'a', c: true, b: 1 },
          { d: 2, b: 1 }
        ])
    end

    def test_insert_values_array
      expected <<~SQL
        INSERT INTO x VALUES ('a', 1, true, NULL)
      SQL
      "INSERT INTO x %values".quote_sql(values: [['a', 1, true, nil]])
    end

    def test_insert_values_hash
      expected <<~SQL
        INSERT INTO x ("a", "b", "c", "d") VALUES ('a', 1, true, NULL)
      SQL
      "INSERT INTO x %values".quote_sql(values: [{ a: 'a', b: 1, c: true, d: nil }])
    end

    # def test_q3
    #   expected Arel.sql(<<-SQL)
    #         INSERT INTO "responses" ("id","type","task_id","index","data","parts","value","created_at","updated_at")
    #         VALUES (NULL,TRUE,'A','[5,5]','{"a":1}'),
    #                (1,FALSE,'B','[]','{"a":2}'),
    #                (2,NULL,'c','[1,2,3]','{"a":3}')
    #         ON CONFLICT (responses_task_id_index_unique) DO NOTHING;
    #     SQL
    #
    #   QuoteSql.new(<<-SQL).
    #       INSERT INTO %table (%columns) VALUES %values
    #         ON CONFLICT (responses_task_id_index_unique) DO NOTHING;
    #     SQL
    #     quote(
    #       table: Response,
    #       values: [
    #         [nil, true, "A", [5, 5], { a: 1 }],
    #         [1, false, "B", [], { a: 2 }],
    #         [2, nil, "c", [1, 2, 3], { a: 3 }]
    #       ]
    #     )
    # end
  end
end