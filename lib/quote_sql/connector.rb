class QuoteSql
  module Connector
    def self.set(klass)
      file = "/" + klass.to_s.underscore.tr("/", "_")
      require __FILE__.sub(/\.rb$/, file)
      const_set :CONNECTOR, (to_s + file.classify).constantize
      QuoteSql.include CONNECTOR
      class << QuoteSql
        prepend CONNECTOR::ClassMethods
      end
    end
  end
end
