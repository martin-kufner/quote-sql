module QuoteSql::Test
  def self.all
    methods(false).grep(/^test_/).each do |name|
      run(name)
      puts
    end

  end

  def self.run(name)
    name = name.to_s.sub(/^test_/, "")
    @expected = nil
    @test = send("test_#{name}")
    if sql.gsub(/\s+/, "") == expected&.gsub(/\s+/, "")
      STDOUT.puts name, @test.original, @test.quotes.inspect, "✅ #{expected}"
    else
      STDOUT.puts name, @test.inspect, sql, "❌ #{expected}"
    end
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
      expected Arel.sql(%(SELECT "a","b"."c" FROM "my_table"))
      QuoteSql.new("SELECT %columns FROM %table_name").quote(
        columns: [:a, b: :c],
        table_name: "my_table"
      )
    end

    def test_columns_and_table_name_complex
      expected Arel.sql(%(SELECT "a","b"."c" FROM "table1","table2"))
      QuoteSql.new("SELECT %columns FROM %table_names").quote(
        columns: [:a, b: :c],
        table_names: ["table1", "table2"]
      )
    end

    def test_recursive_injects
      expected Arel.sql(%(SELECT TRUE FROM "table1"))
      QuoteSql.new("SELECT %raw FROM %table_names").quote(
        raw: "%recurse1_raw",
        recurse1_raw: "%recurse2",
        recurse2: true,
        table_names: "table1"
      )
    end

    def test_values
      expected Arel.sql(%(SELECT 'a text', 123, 'text' AS abc FROM "my_table"))
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
      expected Arel.sql(%(SELECT $1, $2, $1 AS get_bind_1_again FROM "my_table"))
      QuoteSql.new("SELECT %bind, %bind__uuid, %bind1 AS get_bind_1_again FROM %table_name").quote(
        table_name: "my_table"
      )
    end

    def test_q3
      expected Arel.sql(<<-SQL)
            INSERT INTO "responses" ("id","type","task_id","index","data","parts","value","created_at","updated_at") 
            VALUES (NULL,TRUE,'A','[5,5]','{"a":1}'),
                   (1,FALSE,'B','[]','{"a":2}'),
                   (2,NULL,'c','[1,2,3]','{"a":3}')
            ON CONFLICT (responses_task_id_index_unique) DO NOTHING;
        SQL

      QuoteSql.new(<<-SQL).
          INSERT INTO %table (%columns) VALUES %values
            ON CONFLICT (responses_task_id_index_unique) DO NOTHING;
        SQL
        quote(
          table: Response,
          values: [
            [nil, true, "A", [5, 5], { a: 1 }],
            [1, false, "B", [], { a: 2 }],
            [2, nil, "c", [1, 2, 3], { a: 3 }]
          ]
        )
    end
  end
end