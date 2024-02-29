class QuoteSql::Test
  private

  def test_columns
    expected <<~SQL
      SELECT x, "a", "b", "c", "d"
    SQL
    "SELECT x, %x_columns ".quote_sql(x_columns: %i[a b c d])
  end

  def test_columns_and_table_name_simple
    expected <<~SQL
      SELECT "my_table"."a", "b", "gaga"."c", "my_table"."e" AS "d", "gaga"."d" AS "f", 1 + 2 AS "g", whatever AS raw FROM "my_table"
    SQL
    QuoteSql.new("SELECT %columns FROM %table").quote(
      columns: [:a, "b", "gaga.c", { d: :e, f: "gaga.d", g: Arel.sql("1 + 2") }, Arel.sql("whatever AS raw")],
      table: "my_table"
    )
  end

  def test_columns_and_table_name_complex
    expected <<~SQL
      SELECT "table1"."a","table1"."c" as "b" FROM "table1","table2"
    SQL
    QuoteSql.new("SELECT %columns FROM %table").quote(
      columns: [:a, b: :c],
      table: ["table1", "table2"]
    )
  end

  def test_recursive_injects
    expected %(SELECT TRUE FROM "table1")
    QuoteSql.new("SELECT %raw FROM %table").quote(
      raw: "%recurse1_raw",
      recurse1_raw: "%recurse2",
      recurse2: true,
      table: "table1"
    )
  end

  def test_values
    expected <<~SQL
      SELECT 'a text', 123, '{"abc":"don''t"}'::jsonb FROM "my_table"
    SQL
    QuoteSql.new("SELECT %text, %{number}, %hash FROM %table").quote(
      text: "a text",
      number: 123,
      hash: { abc: "don't" },
      table: "my_table"
    )
  end

  # def test_binds
  #   expected <<~SQL
  #     SELECT $1, $2::UUID, $1 AS get_bind_1_again FROM "my_table"
  #   SQL
  #   QuoteSql.new("SELECT %bind, %bind__uuid, %bind1 AS get_bind_1_again FROM %table").quote(
  #     table: "my_table"
  #   )
  # end

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
      SELECT * 
            FROM (VALUES 
                        ('a'::TEXT, 1::INTEGER, true::BOOLEAN, NULL::FLOAT), 
                        ('a', 1, true, NULL), 
                        (NULL, 1, NULL, 2)
                  ) AS "x" ("a", "b", "c", "d")
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

  def test_from_json
    expected <<~SQL
      SELECT * FROM json_to_recordset('[{"a":1,"b":"foo"},{"a":"2"}]') as "x" ("a" int, "b" text)
    SQL
    "SELECT * FROM %x_json".quote_sql(x_casts: { a: "int", b: "text" }, x_json: [{ a: 1, b: 'foo' }, { a: '2', c: 'bar' }])
  end

  def test_json_insert
    expected <<~SQL
      INSERT INTO users (name, color) SELECT * from json_to_recordset('[{"name":"auge","color":"#611333"}]') AS "x"("name" text,"color" text)
    SQL
    x_json = { "first_name" => nil, "last_name" => nil, "stripe_id" => nil, "credits" => nil, "avatar" => nil, "name" => "auge", "color" => "#611333", "founder" => nil, "language" => nil, "country" => nil, "data" => {}, "created_at" => "2020-11-19T09:30:18.670Z", "updated_at" => "2020-11-19T09:40:00.063Z" }
    "INSERT INTO users (name, color) SELECT * from %x_json".quote_sql(x_casts: { name: "text", color: "text" }, x_json:)
  end

  def test_from_json_bind
    expected <<~SQL
      Select * From json_to_recordset($1) AS "x"("a" int,"b" text,"c" boolean)
    SQL
    QuoteSQL("Select * From %x_json", x_json: 1, x_casts: { a: "int", b: "text", c: "boolean" })
  end

  def test_insert_json_bind
    expected <<~SQL
      INSERT INTO table ("a","b","c") Select * From json_to_recordset($1) AS "x"("a" int,"b" text,"c" boolean)  
    SQL
    QuoteSQL("INSERT INTO table (%x_columns) Select * From %x_json", x_json: 1, x_casts: { a: "int", b: "text", c: "boolean" })
  end

  def test_cast_values
    expected <<~SQL
      SELECT 
         'abc'::TEXT, 
         '"abc"'::JSON, 
         '["cde",null,"fgh"]'::JSONB,
         ARRAY['cde', NULL, 'fgh']::TEXT[],  
         ARRAY['"cde"', 'null', '"fgh"']::JSON[],
         '{"foo":"bar","go":1,"strip_null":null}'::JSONB not_compact,
         '{"foo":"bar","go":1}'::JSON compact,
         'foo=>bar,go=>1,strip_null=>NULL'::HSTORE,
        ARRAY[[1,2,3],[1,2,3]]::INT[][]
    SQL
    array1 = array2 = array3 = ["cde", nil, "fgh"]
    array4 = [[1,2,3], [1,2,3]]
    hash = { foo: "bar", "go": 1, strip_null: nil }
    QuoteSQL(<<~SQL, field1: 'abc', array1:, array2:, array3:, array4:, hash: ,not_compact: hash, compact: hash.merge(nil => false))
      SELECT 
        %field1::TEXT, 
        %field1::JSON,
        %array1,
        %array2::TEXT[],
        %array3::JSON[], 
        %not_compact not_compact,
        %compact::JSON compact,
        %hash::HSTORE,
        %array4::INT[][]
    SQL
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

  public

  def all
    @success = []
    @fail = []
    private_methods(false).grep(/^test_/).each { run(_1, true) }
    @success.each { STDOUT.puts(*_1, nil) }
    @fail.each { STDOUT.puts(*_1, nil) }
    puts
  end

  def run(name, all = false)
    name = name.to_s.sub(/^test_/, "")
    rv = ["🧪 #{name}"]
    @expected = nil
    @test = send("test_#{name}")
    if sql.gsub(/\s+/, "")&.downcase&.strip == expected&.gsub(/\s+/, "")&.downcase&.strip
      tables = @test.tables.to_h { [[_1, "table"].compact.join("_"), _2] }
      columns = @test.instance_variable_get(:@columns).to_h { [[_1, "columns"].compact.join("_"), _2] }
      rv += [
        "QuoteSql.new(\"#{@test.original}\").quote(#{{ **tables, **columns, **@test.quotes }.inspect}).to_sql", "🎯 #{expected}", "✅ #{sql}"]
      @success << rv if @success
    else
      rv += [@test.inspect, "🎯 #{expected}", "❌ #{sql}"]
      rv << sql.gsub(/\s+/, "")&.downcase&.strip
      rv << expected&.gsub(/\s+/, "")&.downcase&.strip
      @fail << rv if @fail
    end
  rescue => exc
    rv += [@test.inspect, "🎯 #{expected}", "❌ #{sql}", exc.message]
    @fail << rv if @fail
  ensure
    STDOUT.puts(*rv) unless @fail or @success
  end

  def expected(v = nil)
    @expected ||= v
  end

  def sql
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

  def datatype
    errors = {}
    success = []
    spaces = ->(*) { " " * (rand(4) + 1) }

    DATATYPES.each_line(chomp: true) do |line|

      l = line.gsub(/\s+/, &spaces).gsub(/(?<=\()\d+|\d+(?=\))/) { "#{spaces.call}#{rand(10) + 1}#{spaces.call}" }.gsub(/\(/) { "#{spaces.call}(" }

      m = "jgj hsgjhsgfjh ag %field::#{l} asldfalskjdfl".match(QuoteSql::CASTS)
      if m.present? and l == m[1]
          success << line
        else
          errors[line] = m&.to_a
      end
      line = line + "[]"*(rand(3) + 1)
      m = "jgj hsgjhsgfjh ag %field::#{line} asldfalskjdfl".match(QuoteSql::CASTS)
      if m.present? and line == m[1] + m[2]
        success << line
      else
        errors[line] = m&.to_a
      end
    end
    puts success.sort.inspect
    ap errors
  end

  DATATYPES = <<-DATATYPES
bigint
int8
bigserial
serial8
bit
bit (1)
bit varying
varbit
bit varying (2)
varbit (2)
boolean
bool
box
bytea
character
char
character (1)
char (1)
character varying
varchar
character varying (1)
varchar (1)
cidr
circle
date
double precision
float8
inet
integer
int
int4
interval
interval (1)
json
jsonb
line
lseg
macaddr
macaddr8
money
numeric
numeric(10,3)
decimal
decimal(10,3)
path
pg_lsn
pg_snapshot
point
polygon
real
float4
smallint
int2
smallserial
serial
serial2
serial4
text
time
time(1)
time without time zone
time(1) without time zone
time with time zone
time(2) with time zone
timetz
timestamp
timestamp(1)
timestamp without time zone
timestamp(1) without time zone
timestamp with time zone
timestamp(1) with time zone
timestamptz
tsquery
tsvector
txid_snapshot
uuid
xml
  DATATYPES

end
