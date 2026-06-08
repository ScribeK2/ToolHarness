require "date"

module ToolHarness
  module HistoricalDns
    # Value normalization so the same record from two providers dedupes cleanly.
    module Normalize
      module_function

      # Hostname-valued records (NS, MX target, CNAME, SOA): lowercase, drop trailing dot.
      def host(str)
        str.to_s.strip.downcase.chomp(".")
      end

      # MX → "<priority> <host>" so target dedupes while priority stays visible.
      def mx(priority, exchange)
        ex = host(exchange)
        pr = priority.to_s.strip
        pr.empty? ? ex : "#{pr.to_i} #{ex}"
      end

      # TXT/SPF: collapse interior whitespace, strip one layer of wrapping quotes.
      def text(str)
        str.to_s.strip.gsub(/\s+/, " ").gsub(/\A"|"\z/, "")
      end

      # Accepts unix epoch (Int/Numeric/numeric-String), ISO/date String, Date, or nil.
      def date(val)
        case val
        when nil     then nil
        when Date    then val
        when Numeric then Time.at(val).utc.to_date
        else
          s = val.to_s.strip
          return nil if s.empty?
          begin
            Time.at(Integer(s)).utc.to_date
          rescue ArgumentError, TypeError
            (Date.parse(s) rescue nil)
          end
        end
      end
    end
  end
end
