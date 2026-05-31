require "ipaddr"

module ToolHarness
  module HostNormalizer
    SCHEME_RX        = /\Ahttps?:\/\//i
    PATH_OR_QUERY_RX = /[\/?#].*\z/m
    TRAILING_SLASH_RX = /\/+\z/

    def self.call(value, preserve_path: false)
      s = value.to_s.strip
      return s if s.empty?

      # IP literals (incl. bracketed IPv6) bypass scheme/path stripping —
      # the colons in IPv6 would otherwise be mangled as scheme/port.
      unbracketed = s.delete_prefix("[").delete_suffix("]")
      return unbracketed if valid_ip?(unbracketed)

      if s.match?(SCHEME_RX)
        s = s.sub(SCHEME_RX, "")
      elsif s.include?("://")
        return s
      end

      preserve_path ? s.sub(TRAILING_SLASH_RX, "") : s.sub(PATH_OR_QUERY_RX, "")
    end

    def self.valid_ip?(string)
      IPAddr.new(string)
      true
    rescue IPAddr::Error
      false
    end
  end
end
