
Gem::Specification.new do |s|
  s.name        = "quote-sql"
  s.version     = "0.0.3"
  s.summary     = "Tool to build and run SQL queries easier"
  s.description = <<~TEXT
QuoteSql helps you creating SQL queries and proper quoting especially with advanced queries.
  TEXT
  s.authors     = ["Martin Kufner"]
  s.email       = "martin.kufner@quiz.baby"
  s.files = Dir["lib/**/*", "README.md"]
  s.homepage    = "https://github.com/martin-kufner/quote-sql"
  s.license     = "MIT"
  s.required_ruby_version = '~> 3.0'
end