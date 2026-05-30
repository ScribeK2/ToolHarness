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

    # Returns an RDAP base URL (trailing slash preserved) or nil.
    def base_for(query, record_type)
      case record_type
      when :domain then domain_base(query)
      when :ip     then ip_base(query)
      else nil
      end
    end

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

    def domain_base(domain)
      services = dns_services
      return nil unless services.is_a?(Hash)
      labels = domain.to_s.downcase.chomp(".").split(".")
      # Try the longest suffix first: "a.b.co.uk" -> "a.b.co.uk","b.co.uk","co.uk","uk"
      labels.each_index do |i|
        candidate = labels[i..].join(".")
        services["services"].to_a.each do |(tlds, urls)|
          return urls.first if Array(tlds).map(&:downcase).include?(candidate)
        end
      end
      nil
    end

    def ip_base(ip_string)
      addr = IPAddr.new(ip_string.to_s)
      services = addr.ipv6? ? ipv6_services : ipv4_services
      return nil unless services.is_a?(Hash)

      best_url = nil
      best_prefix = -1
      services["services"].to_a.each do |(cidrs, urls)|
        Array(cidrs).each do |cidr|
          block = IPAddr.new(cidr)
          next unless block.include?(addr)
          prefix = cidr.split("/").last.to_i
          if prefix > best_prefix
            best_prefix = prefix
            best_url = urls.first
          end
        end
      end
      best_url
    rescue IPAddr::Error
      nil
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
