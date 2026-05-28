module ToolHarness
  module HostNormalizer
    SCHEME_RX        = /\Ahttps?:\/\//i
    PATH_OR_QUERY_RX = /[\/?#].*\z/m
    TRAILING_SLASH_RX = /\/+\z/

    def self.call(value, preserve_path: false)
      s = value.to_s.strip
      return s if s.empty?

      if s.match?(SCHEME_RX)
        s = s.sub(SCHEME_RX, "")
      elsif s.include?("://")
        return s
      end

      preserve_path ? s.sub(TRAILING_SLASH_RX, "") : s.sub(PATH_OR_QUERY_RX, "")
    end
  end
end
