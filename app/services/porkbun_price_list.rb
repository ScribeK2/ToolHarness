require "json"

# Resolves a domain's TLD to Porkbun registration/renewal/transfer pricing
# (USD) from the bundled snapshot at config/porkbun_pricing.json — refreshed
# dev-side by script/refresh-porkbun-pricing, typically at release time.
#
# Why a snapshot instead of a live fetch: Porkbun's edge blocks Ruby's TLS
# fingerprint at runtime — silent read-stalls on the api./api-ipv4. hosts and
# a 403 from the main host, while plain curl from the same machine succeeds
# (verified live 2026-07-16). Nothing Ruby-shaped gets through, so the app
# never fetches at runtime. Each price carries the snapshot's fetched_at date
# (:as_of) so staleness stays visible; TLD base prices change rarely.
#
# Standard TLD pricing only. Porkbun's public endpoint has no per-domain
# premium/aftermarket pricing (that requires an authenticated account-level
# call, out of scope) — a premium domain reports its TLD's ordinary price,
# not its real cost.
class PorkbunPriceList
  PATH = Rails.root.join("config/porkbun_pricing.json")

  def self.price_for(domain) = new.price_for(domain)

  def initialize(path: PATH)
    @path = path
  end

  # Returns { tld:, registration:, renewal:, transfer:, as_of: } (USD floats,
  # ISO date string) for the domain's TLD, or nil if the TLD isn't priced by
  # Porkbun or the snapshot is missing/unreadable.
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

  # The snapshot's fetch date (ISO string), or nil when unreadable.
  def snapshot_date = snapshot["fetched_at"]

  private

  def pricing
    p = snapshot["pricing"]
    p.is_a?(Hash) ? p : nil
  end

  def snapshot
    @snapshot ||= begin
      JSON.parse(File.read(@path))
    rescue StandardError => e
      Rails.logger.warn("PorkbunPriceList snapshot unreadable (#{@path}): #{e.class}: #{e.message}")
      {}
    end
  end

  def build(tld, entry)
    {
      tld: tld,
      registration: entry["registration"]&.to_f,
      renewal: entry["renewal"]&.to_f,
      transfer: entry["transfer"]&.to_f,
      as_of: snapshot_date
    }
  end
end
