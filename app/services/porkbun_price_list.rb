require "net/http"
require "json"

# Resolves a domain's TLD to Porkbun's public no-auth registration/renewal/
# transfer pricing (USD) — api.porkbun.com/api/json/v3/pricing/get, no API
# key or account required. Mirrors Rdap::Bootstrap's cache-and-degrade
# pattern: the full price list is Rails.cache-backed for 24h; only a
# successful fetch is cached (so a failed fetch is retried next call rather
# than caching the failure); with no cached copy and a failed fetch,
# price_for returns nil rather than raising.
#
# Standard TLD pricing only. Porkbun's public endpoint has no per-domain
# premium/aftermarket pricing (that requires an authenticated account-level
# call, out of scope) — a premium domain reports its TLD's ordinary price,
# not its real cost.
class PorkbunPriceList
  URL = "https://api.porkbun.com/api/json/v3/pricing/get".freeze
  CACHE_KEY = "porkbun:pricing".freeze
  CACHE_TTL = 24.hours
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 10

  def self.price_for(domain) = new.price_for(domain)

  # Returns { tld:, registration:, renewal:, transfer: } (USD floats) for the
  # domain's TLD, or nil if the TLD isn't priced by Porkbun or the price list
  # is unavailable.
  def price_for(domain)
    prices = pricing
    return nil unless prices

    labels = domain.to_s.downcase.chomp(".").split(".")
    labels.each_index do |i|
      candidate = labels[i..].join(".")
      entry = prices[candidate]
      return build(candidate, entry) if entry
    end
    nil
  end

  private

  def pricing
    hit = Rails.cache.read(CACHE_KEY)
    return hit if hit

    val = fetch
    Rails.cache.write(CACHE_KEY, val, expires_in: CACHE_TTL) if val
    val
  end

  def build(tld, entry)
    {
      tld: tld,
      registration: entry["registration"]&.to_f,
      renewal: entry["renewal"]&.to_f,
      transfer: entry["transfer"]&.to_f
    }
  end

  # The single HTTP seam — stub this in tests. Returns
  # { "<tld>" => { "registration" =>, "renewal" =>, "transfer" => }, ... } or nil.
  def fetch
    uri = URI.parse(URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT

    req = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json")
    req.body = "{}"
    resp = http.request(req)
    return nil unless resp.is_a?(Net::HTTPSuccess)

    body = JSON.parse(resp.body)
    return nil unless body["status"] == "SUCCESS" && body["pricing"].is_a?(Hash)

    body["pricing"]
  rescue StandardError
    nil
  end
end
