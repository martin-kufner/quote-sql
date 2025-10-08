class QuoteSql::Test
  private

  def test_columns
    expected <<~SQL
      SELECT x, "a", "b", "c", "d"
    SQL
    "SELECT x, $x_columns ".quote_sql(x_columns: %i[a b c d])
  end

  def test_columns_and_table_name_simple
    expected <<~SQL
      SELECT "my_table"."a", "b", "gaga"."c", "my_table"."e" AS "d", "gaga"."d" AS "f", 1 + 2 AS "g", whatever AS raw FROM "my_table"
    SQL
    QuoteSql.new("SELECT $columns FROM $table").quote(
      columns: [:a, "b", "gaga.c", { d: :e, f: "gaga.d", g: Arel.sql("1 + 2") }, Arel.sql("whatever AS raw")],
      table: "my_table"
    )
  end

  def test_columns_and_table_name_complex
    expected <<~SQL
      SELECT "table1"."a","table1"."c" as "b" FROM "table1","table2"
    SQL
    QuoteSql.new("SELECT $columns FROM $table").quote(
      columns: [:a, b: :c],
      table: ["table1", "table2"]
    )
  end

  def test_recursive_injects
    expected %(SELECT TRUE FROM "table1")
    QuoteSql.new("SELECT $raw FROM $table").quote(
      raw: "$recurse1_raw",
      recurse1_raw: "$recurse2",
      recurse2: true,
      table: "table1"
    )
  end

  def test_values
    expected <<~SQL
      SELECT 'a text', 123, '{"abc":"don''t"}'::jsonb FROM "my_table"
    SQL
    QuoteSql.new("SELECT $text, ${number}, $hash FROM $table").quote(
      text: "a text",
      number: 123,
      hash: { abc: "don't" },
      table: "my_table"
    )
  end

  def test_values_hash_active_record
    table = create_active_record_class("tasks") do |t|
      t.text :name
      t.integer :n1, default: 1, null: false
      t.virtual :v1, type: :boolean, stored: true, as: "FALSE"
      t.timestamps
    end
    updated_at = Date.new(2024,1,1)
    expected <<~SQL
        INSERT INTO "tasks" ("id", "name", "n1", "created_at", "updated_at") VALUES (DEFAULT, 'Task1', 1, DEFAULT, DEFAULT), (DEFAULT, 'Task2', DEFAULT, DEFAULT, '2024-01-01')
    SQL
    insert_values = [
                {n1: 1, name: "Task1"},
                {name: "Task2", updated_at: }
    ]
    QuoteSql.new(<<~SQL).quote(table:, insert_values:)
        INSERT INTO $table $insert_values
    SQL
  end

  def test_values_hash_active_record_select_columns
    table = create_active_record_class("tasks") do |t|
      t.text :name
      t.integer :n1, default: 1, null: false
      t.virtual :v1, type: :boolean, stored: true, as: "FALSE"
      t.timestamps
    end
    expected <<~SQL
        INSERT INTO "tasks" ("name") VALUES ('Task1'), ('Task2')
    SQL
    insert_values = [
      {n1: 1, name: "Task1"},
      {name: "Task2", id: "12345" }
    ]
    QuoteSql.new(<<~SQL).quote(table:, insert_values:, columns: %i[name])
        INSERT INTO $table $insert_values
    SQL
  end


  def test_from_values_hash_no_columns
    expected <<~SQL
      SELECT * FROM (VALUES ('a', 1, true, NULL), ('a', 1, true, NULL), (NULL, 1, NULL, 2)) AS "y" ("a", "b", "c", "d")
    SQL
    "SELECT * FROM $y_values".quote_sql(y_values: [
      { a: 'a', b: 1, c: true, d: nil },
      { d: nil, a: 'a', c: true, b: 1 },
      { d: 2, b: 1 }
    ])
  end

  def test_from_values_hash_with_columns
    expected <<~SQL
      SELECT * FROM (VALUES (NULL, true, 1, 'a')) AS "x" ("d","c","b","a")
    SQL
    "SELECT * FROM $x_values".quote_sql(x_columns: %i[d c b a], x_values: [{ a: 'a', b: 1, c: true, d: nil }])
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
    "SELECT * FROM $x_values".quote_sql(
      x_casts: {
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


  def test_insert_values_hash
    expected <<~SQL
      INSERT INTO x ("a", "b", "c", "d") VALUES ('a', 1, true, NULL)
    SQL
    "INSERT INTO x $insert_values".quote_sql(insert_values: [{ a: 'a', b: 1, c: true, d: nil }])
  end

  def test_from_json
    expected <<~SQL
      SELECT * FROM json_to_recordset('[{"a":1,"b":"foo"},{"a":"2"}]') as "x" ("a" int, "b" text)
    SQL
    "SELECT * FROM $x_json".quote_sql(x_casts: { a: "int", b: "text" }, x_json: [{ a: 1, b: 'foo' }, { a: '2', c: 'bar' }])
  end

  def test_json_insert
    expected <<~SQL
      INSERT INTO users ("name", "color") SELECT * from json_to_recordset('[{"name":"auge","color":"#611333"}]') AS "json"("name" text,"color" text)
    SQL
    json = { "first_name" => nil, "last_name" => nil, "stripe_id" => nil, "credits" => nil, "avatar" => nil, "name" => "auge", "color" => "#611333", "founder" => nil, "language" => nil, "country" => nil, "data" => {}, "created_at" => "2020-11-19T09:30:18.670Z", "updated_at" => "2020-11-19T09:40:00.063Z" }
    "INSERT INTO users ($columns) SELECT * from $json".quote_sql(columns: %i[name color], json:)
  end

  def test_from_json_bind
    expected <<~SQL
      Select * From json_to_recordset($1) AS "x"("a" int,"b" text,"c" boolean)
    SQL
    QuoteSQL("Select * From $x_json", x_json: 1, x_casts: { a: "int", b: "text", c: "boolean" })
  end

  def test_insert_json_bind
    expected <<~SQL
      INSERT INTO table ("a","b","c") Select * From json_to_recordset($1) AS "x"("a" int,"b" text,"c" boolean)  
    SQL
    QuoteSQL("INSERT INTO table ($x_columns) Select * From $x_json", x_json: 1, x_casts: { a: "int", b: "text", c: "boolean" })
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
    array4 = [[1, 2, 3], [1, 2, 3]]
    hash = { foo: "bar", "go": 1, strip_null: nil }
    QuoteSQL(<<~SQL, field1: 'abc', array1:, array2:, array3:, array4:, hash:, not_compact: hash, compact: hash.merge(nil => false))
      SELECT 
        $field1::TEXT, 
        $field1::JSON,
        $array1,
        $array2::TEXT[],
        $array3::JSON[], 
        $not_compact not_compact,
        $compact::JSON compact,
        $hash::HSTORE,
        $array4::INT[][]
    SQL
  end

  def test_columns_with_tables
    expected <<~SQL
      SELECT "profiles"."a", "profiles"."b",
          "relationships"."a", "relationships"."b",
          relationship_timestamp("relationships".*)
    SQL

    profile_table = "profiles"
    relationship_table = "relationships"
    relationship_columns = profile_columns = %i[a b]

    <<~SQL.quote_sql(profile_columns:, profile_table:, relationship_columns:, relationship_table:)
      SELECT $profile_columns, $relationship_columns, 
        relationship_timestamp($relationship_table.*)
    SQL
  end

  def test_bulk_update
    # UPDATE "slot_responses"
    # SET
    # FROM (VALUES (FALSE,1),(FALSE,1)) AS "v" ("active","response_id")
    # WHERE "slot_responses".response_id = v.response_id
  end



  def test_active_record
    table = create_active_record_class("users") do |t|
      t.text :first_name
      t.integer :n1, default: 1, null: false
      t.virtual :v1, type: :boolean, stored: true, as: "FALSE"
      t.timestamps default: -> {"CURRENT_TIMESTAMP"} , null: false
    end
    expected <<~SQL
      SELECT "id", "first_name", "n1", "v1", "created_at", "updated_at" FROM "users"
    SQL
    <<~SQL.quote_sql(table:)
        SELECT $columns FROM $table
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
  #       INSERT INTO $table ($columns) VALUES $insert_values
  #         ON CONFLICT (responses_task_id_index_unique) DO NOTHING;
  #     SQL
  #     quote(
  #       table: Response,
  #       insert_values: [
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
    puts(*rv)
    @expected = nil
    @test = send("test_#{name}")
    if sql.gsub(/\s+/, "")&.downcase&.strip == expected&.gsub(/\s+/, "")&.downcase&.strip
      # tables = @test.tables.to_h { [[_1, "table"].compact.join("_"), _2] }
      # columns = @test.instance_variable_get(:@columns).to_h { [[_1, "columns"].compact.join("_"), _2] }
      #"QuoteSql.new(\"#{@test.original}\").quote(#{{ **tables, **columns, **@test.quotes }.inspect}).to_sql",
        rv += ["🎯 #{expected}", "✅ #{sql}"]

      @success << rv if @success
    else
      rv += [@test.inspect, "🎯 #{expected}", "❌ #{sql}"]
      rv << "🎯 " + expected&.gsub(/\s+/, "")&.downcase&.strip
      rv << "❌ " + sql.gsub(/\s+/, "")&.downcase&.strip
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

  class PseudoActiveRecordKlass
    class Column
      def initialize(name, type, **options)
        @name = name.to_s
        @type = type
        @null = options[:null]
        type = options[:type] if @type == :virtual
        @sql_type = DATATYPES[/^#{type}$/]
        unless @type == :virtual or options[:default].nil?
         @default = options[:default]
        end
      end

      attr_reader :name, :type, :sql_type, :null, :default, :default_function

      def default?
        ! (@default || @default_function).nil?
      end
    end
    class Columns
      def initialize(&block)
        @rv = []
        block.call(self)
      end

      def to_a
        @rv
      end

      def timestamps(**options)
        @rv << Column.new( :created_at, :timestamp, null: false, **options)
        @rv << Column.new( :updated_at, :timestamp, null: false, **options)
      end

      def method_missing(type, name, *args, **options)
        @rv << Column.new(name, type, *args, **options)
      end
    end

    def initialize(table_name, id: :uuid, &block)
      @table_name = table_name
      @columns = Columns.new(&block).to_a
      unless id.nil? or id == false
        @columns.unshift(Column.new("id", *[id], null: false, default: "gen_random_uuid()"))
      end
    end

    attr_reader :table_name, :columns

    def column_names
      @columns.map { _1.name }
    end
  end

  def create_active_record_class(table_name, **options, &block)
     PseudoActiveRecordKlass.new(table_name, **options, &block)
  end


  def datatype
    errors = {}
    success = []
    spaces = ->(*) { " " * (rand(4) + 1) }

    DATATYPES.each_line(chomp: true) do |line|

      l = line.gsub(/\s+/, &spaces).gsub(/(?<=\()\d+|\d+(?=\))/) { "#{spaces.call}#{rand(10) + 1}#{spaces.call}" }.gsub(/\(/) { "#{spaces.call}(" }

      m = "jgj hsgjhsgfjh ag $field::#{l} asldfalskjdfl".match(QuoteSql::CASTS)
      if m.present? and l == m[1]
        success << line
      else
        errors[line] = m&.to_a
      end
      line = line + "[]" * (rand(3) + 1)
      m = "jgj hsgjhsgfjh ag $field::#{line} asldfalskjdfl".match(QuoteSql::CASTS)
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
