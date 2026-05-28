module ToolHarness
  module HostNormalizer
    SCHEME_RX        = /\Ahttps?:\/\//i
    PATH_OR_QUERY_RX = /[\/?#].*\z/m
    TRAILING_SLASH_RX = /\/+\z/

    def self.call(value, preserve_path: false)
      s = value.to_s.strip
      stripped = s.sub(SCHEME_RX, "")
      scheme_removed = stripped != s
      s = stripped
      return s if s.empty?
      return s unless scheme_removed || !s.include?("://")

      if preserve_path
        s.sub(TRAILING_SLASH_RX, "")
      else
        s.sub(PATH_OR_QUERY_RX, "")
      end
    end
  end
end
