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
    def escape_regex(regexp)
      # https://gist.github.com/glv/24bedd7d39f16a762528d7b30e366aa7
      pregex = regexp.to_s.gsub(/^\(\?-?[mix]+:|\)$/, '')
      if pregex[/[*+?}]\+|\(\?<|&&|\\k|\\g|\\p\{/]
        raise RegexpError, "cant convert Regexp #{sub}"
      end
      pregex.gsub!(/\\h/, "[[:xdigit:]]")
      pregex.gsub!(/\\H/, "[^[:xdigit:]]")
      pregex.gsub!(/\?[^>]>/, '')
      pregex.gsub!(/\{,/, "{0,")
      pregex.gsub!(/\\z/, "\\Z")
      quote(pregex)
    end
  end
end