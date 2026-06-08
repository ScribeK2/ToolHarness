module ToolHarness
  module HistoricalDns
    # WhoisFreaks historical DNS (the only NS/MX history source). Paid API key.
    # One credit per record type; defaults to the migration-relevant set to conserve
    # the 500 free credits (cname/spf/soa deferred — SPF lives in TXT).
    class Whoisfreaks < Provider
      def self.id            = "whoisfreaks"
      def self.display_name  = "WhoisFreaks"
      def self.requires_key? = true
      def self.record_types  = %i[a aaaa ns mx txt]

      MAX_PAGES = 3
      PAGE_SIZE = 100

      def fetch(domain, key:)
        d = Normalize.host(domain)
        records = self.class.record_types.flat_map { |rtype| fetch_type(d, rtype, key) }
        { records: records, subdomains: [] }
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
          rows = Array(body["dnsRecords"] || body["dns_records"])
          rows.each { |row| (rec = build_record(rtype, row)) && out << rec }
          page += 1
          break if rows.size < PAGE_SIZE || page > MAX_PAGES
        end
        out
      end

      def build_record(rtype, row)
        value = record_value(rtype, row)
        return nil if value.to_s.empty?
        Record.new(
          type:       rtype,
          value:      value,
          first_seen: Normalize.date(row["firstSeen"] || row["first_seen"] || row["createdDate"] || row["update_date"]),
          last_seen:  Normalize.date(row["lastSeen"]  || row["last_seen"]  || row["updatedDate"] || row["update_date"]),
          sources:    [self.class.id]
        )
      end

      def record_value(rtype, row)
        case rtype
        when :mx
          Normalize.mx(row["priority"] || row["preference"], row["target"] || row["exchange"] || row["value"] || row["rawText"])
        when :ns, :cname
          Normalize.host(row["target"] || row["value"] || row["rawText"])
        when :a, :aaaa
          (row["address"] || row["value"] || row["rawText"]).to_s.strip
        else # :txt, :spf
          Normalize.text(row["rawText"] || row["value"] || row["text"])
        end
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
