
Gem::Specification.new do |s|
  s.name        = "quote-sql"
  s.version     = "0.0.0"
  s.summary     = "Tool to build and run SQL queries easier"
  s.description = <<~TEXT
I've built this library as an addition to ActiveRecord and Arel, however you can use it with any sql database and plain Ruby.
Creating SQL queries and proper quoting becomes complicated especially when you need advanced queries.
I created this library while coding for different projects, and had lots of Heredoc SQL queries, which pretty quickly becomes the kind of:
> When I wrote these lines of code, just me and God knew what they mean. Now its just God.
My strategy is to segment SQL Queries in readable junks, which can be individually tested and then combine their sql to the final query.

QuoteSql is used in production, but is still evolving.
If you think QuoteSql is interesting, let's chat! Also if you have problems using it, just drop me a note.

Best Martin
  TEXT
  s.authors     = ["Martin Kufner"]
  s.email       = "martin.kufner@quiz.baby"
  s.files = Dir["lib/**/*", "README.md"]
  s.homepage    = "https://github.com/martin-kufner/quote-sql"
  s.license     = "MIT"
end