module ToolHarness
  module HistoricalDns
    # mnemonic PassiveDNS v3 (https://api.mnemonic.no/pdns/v3/<query>). Free, no API key,
    # no per-minute rate-limit pain for normal use — so this is the zero-config source of
    # real A/AAAA/CNAME *history* (first/last seen). Passive-DNS sensors don't observe
    # NS/MX, so those types never appear here (use Whoisfreaks for NS/MX history, or
    # Livedns for the current NS/MX snapshot).
    class Mnemonic < Provider
      def self.id            = "mnemonic"
      def self.display_name  = "mnemonic"
      def self.requires_key? = false
      def self.record_types  = %i[a aaaa cname]

      LIMIT       = 1000
      RRTYPE_MAP  = { "a" => :a, "aaaa" => :aaaa, "cname" => :cname }.freeze

      def fetch(domain, key: nil)
        d    = Normalize.host(domain)
        resp = http_get_json("https://api.mnemonic.no/pdns/v3/#{d}?limit=#{LIMIT}")
        raise_for_status(resp[:status], resp[:error]) unless resp[:status] == 200
        body = resp[:body]
        return { records: [], subdomains: [] } unless body.is_a?(Hash)

        records = Array(body["data"]).filter_map { |row| record_for(row, d) }
        { records: records, subdomains: [] }
      end

      private

      # Keep only forward rows (the queried name is OUR domain) of a type we model. Reverse
      # rows — where the domain is merely the ANSWER (ptr/cname pointing at us) — are dropped.
      def record_for(row, domain)
        return nil unless Normalize.host(row["query"]) == domain
        type = RRTYPE_MAP[row["rrtype"].to_s.downcase]
        return nil unless type

        value = type == :cname ? Normalize.host(row["answer"]) : row["answer"].to_s.strip
        return nil if value.empty?

        Record.new(type: type, value: value,
          first_seen: from_millis(row["firstSeenTimestamp"], row["createdTimestamp"]),
          last_seen:  from_millis(row["lastSeenTimestamp"], row["lastUpdatedTimestamp"]),
          sources: [self.class.id])
      end

      # mnemonic timestamps are epoch milliseconds; Normalize.date treats Numerics as seconds.
      # firstSeen/lastSeen intermittently come back as 0 — fall back to created/lastUpdated
      # (always populated) so we date the record instead of emitting 1970.
      def from_millis(*candidates)
        ms = candidates.find { |c| c.is_a?(Numeric) && c.positive? }
        ms && Normalize.date(ms / 1000)
      end
    end
  end
end
