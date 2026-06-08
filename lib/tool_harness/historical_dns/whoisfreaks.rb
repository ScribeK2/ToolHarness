module ToolHarness
  module HistoricalDns
    # WhoisFreaks historical DNS (the only NS/MX history source). Paid API key.
    # One credit per record type; defaults to the migration-relevant set to conserve
    # the 500 free credits (cname/spf/soa deferred — SPF lives in TXT).
    #
    # Response shape (verified live 2026-06-08): the historical endpoint returns
    #   { totalRecords:, totalPages:, currentPage:, historicalDnsRecords: [ <snapshot> ] }
    # where each <snapshot> is { queryTime: "YYYY-MM-DD", dnsRecords: [ <record> ] } and
    # each <record> is { name:, type:, dnsType: "NS", ttl:, rawText: "<BIND line>", singleName: }.
    # The observation date is the snapshot's queryTime — there are NO per-record timestamps —
    # so a (type, value)'s first/last-seen comes from min/max queryTime once merged.
    class Whoisfreaks < Provider
      def self.id            = "whoisfreaks"
      def self.display_name  = "WhoisFreaks"
      def self.requires_key? = true
      # NS/MX first: they're WhoisFreaks' unique value (VT/crt.sh don't provide them),
      # so on the free tier's ~1-req/min limit the most useful types are fetched before a
      # mid-sequence 429 stops us. (cname/spf/soa deferred — SPF lives in TXT.)
      def self.record_types  = %i[ns mx a aaaa txt]

      MAX_PAGES = 5

      # Each record type is a separate request (1 credit). The free tier allows ~1/min, so a
      # full 5-type sweep self-rate-limits: gather what we can and stop on the first 429,
      # returning partial data rather than nothing. Only raise if even the first call is
      # rate-limited (so the orchestrator degrades + doesn't cache an empty result).
      def fetch(domain, key:)
        d = Normalize.host(domain)
        records = []
        fetched = []
        rate_limited = false
        self.class.record_types.each do |rtype|
          records.concat(fetch_type(d, rtype, key))
          fetched << rtype
        rescue ProviderError => e
          raise unless e.category == :rate_limited
          rate_limited = true
          break
        end
        if records.empty? && rate_limited
          raise ProviderError.new(:rate_limited, "WhoisFreaks rate limit reached (free tier is ~1 req/min)")
        end
        # When we stopped early on a 429, report which types we got vs skipped so the tool
        # can show a PARTIAL status instead of a misleading OK.
        skipped = self.class.record_types - fetched
        partial = rate_limited ? { reason: :rate_limited, fetched: fetched, skipped: skipped } : nil
        { records: records, subdomains: [], partial: partial }
      end

      private

      def fetch_type(domain, rtype, key)
        out  = []
        page = 1
        loop do
          url  = "https://api.whoisfreaks.com/v1.0/dns/historical?apiKey=#{key}" \
                 "&domainName=#{domain}&type=#{rtype}&format=json&page=#{page}"
          resp = http_get_json(url)
          detect_no_credits!(resp)
          raise_for_status(resp[:status], resp[:error]) unless resp[:status] == 200
          body = resp[:body]
          break unless body.is_a?(Hash)
          Array(body["historicalDnsRecords"]).each do |snapshot|
            observed_on = Normalize.date(snapshot["queryTime"])
            Array(snapshot["dnsRecords"]).each do |row|
              (rec = build_record(rtype, row, observed_on)) && out << rec
            end
          end
          page += 1
          break if page > body["totalPages"].to_i || page > MAX_PAGES
        end
        out
      end

      def build_record(rtype, row, observed_on)
        value = record_value(rtype, row)
        return nil if value.to_s.empty?
        Record.new(type: rtype, value: value, first_seen: observed_on, last_seen: observed_on,
                   sources: [self.class.id])
      end

      def record_value(rtype, row)
        rd = rdata(row)
        case rtype
        when :mx
          pri, host = rd.split(/\s+/, 2)
          Normalize.mx(pri, host)
        when :ns, :cname
          Normalize.host(rd)
        when :a, :aaaa
          rd.strip
        else # :txt, :spf
          Normalize.text(rd)
        end
      end

      # Extract the RDATA from the full BIND line by anchoring on the "IN" class token:
      #   "google.com.  21600  IN  NS  ns3.google.com."  ->  "ns3.google.com."
      # Falls back to the parsed singleName when rawText is absent/odd.
      def rdata(row)
        parts  = row["rawText"].to_s.split(/\s+/)
        in_idx = parts.index { |p| p.casecmp?("IN") }
        tail   = in_idx ? parts[(in_idx + 2)..] : nil
        tail.present? ? tail.join(" ") : row["singleName"].to_s
      end

      def detect_no_credits!(resp)
        body = resp[:body]
        msg  = body.is_a?(Hash) ? (body["error"] || body["message"]).to_s : ""
        if resp[:status] == 402 || msg.match?(/credit/i)
          raise ProviderError.new(:no_credits, "WhoisFreaks free credits exhausted")
        end
      end
    end
  end
end
