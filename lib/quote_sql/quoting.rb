class QuoteSql
  module Quoting
    def escape(item)
      case item
      when Regexp
        escape_regex(item)
      when Array
        escape_array(item)
      else
        quote(item)
      end
    end

    def escape_array(ary)
      type = nil
      dive = ->(ary) do
        ary.flat_map do |elem|
          if elem.is_a? Array
            dive[s]
          elsif !elem.nil? and (type ||= elem.class.to_s) != elem.class.to_s
            raise TypeError, "Array elements have to be the same kind"
          else
            quote elem
          end
        end.join(',')
      end
      ary = "[#{dive[ary]}]"
      "ARRAY#{ary}"
    end


    # quote ruby regex with a postgres regex
    # @argument regexp [Regex]
    # @return String
    def escape_regex(regexp, json: false)
      raise ArgumentError, "argument is not a Regexp" unless regexp.is_a? Regexp
      # https://gist.github.com/glv/24bedd7d39f16a762528d7b30e366aa7
      flags = ""
      flags << "i" if (regexp.options & Regexp::IGNORECASE) != 0
      flags << "s" if (regexp.options & Regexp::MULTILINE) != 0  # Ruby /m (dotall) entspricht Postgres 's'
      flags << "x" if (regexp.options & Regexp::EXTENDED) != 0

      pregex = regexp.source.gsub(/^\(\?-?[mix]+:|\)$/, '')
      if pregex[/[*+?}]\+|\(\?<|&&|\\k|\\g|\\p\{/]
        raise RegexpError, "cant convert Regexp #{sub}"
      end
      pregex.gsub!(/\\h/, "[[:xdigit:]]")
      pregex.gsub!(/\\H/, "[^[:xdigit:]]")
      pregex.gsub!(/\?[^>]>/, '')
      pregex.gsub!(/\{,/, "{0,")
      pregex.gsub!(/\\z/, "\\Z")

      if json
        pregex.gsub!('"', '\"')
      elsif quote
        pregex = quote(pregex)
      end

      result = String.new(pregex)
      result.define_singleton_method(:flag) { flags }
      result
    end
  end
end