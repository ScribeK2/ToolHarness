require "net/http"
require "json"
require "ipaddr"

module Rdap
  # Resolves an RDAP base URL for a domain or IP using IANA's bootstrap registry
  # (https://data.iana.org/rdap/). Each bootstrap file is cached ~24h. Any fetch
  # failure is non-fatal: callers get nil and fall through to the rdap.org
  # redirector. Never raises to the caller.
  class Bootstrap
    BASE = "https://data.iana.org/rdap".freeze
    CACHE_TTL = 24.hours
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 8

    private

    def dns_services  = cached("dns")  { fetch_json("#{BASE}/dns.json") }
    def ipv4_services = cached("ipv4") { fetch_json("#{BASE}/ipv4.json") }
    def ipv6_services = cached("ipv6") { fetch_json("#{BASE}/ipv6.json") }

    # Cache only non-nil results so a failed fetch is retried next time.
    def cached(name)
      key = "rdap:bootstrap:#{name}"
      hit = Rails.cache.read(key)
      return hit if hit
      val = yield
      Rails.cache.write(key, val, expires_in: CACHE_TTL) if val
      val
    end

    # The single HTTP seam — stub this in tests. Returns a parsed Hash or nil.
    def fetch_json(url)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      resp = http.get(uri.request_uri, "Accept" => "application/json")
      return nil unless resp.is_a?(Net::HTTPSuccess)
      JSON.parse(resp.body)
    rescue StandardError
      nil
    end
  end
end
