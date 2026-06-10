module ToolHarness
  module HistoricalDns
    # Certificate Transparency history (subdomains over time) via SSLMate's Certspotter API.
    # No API key, and far more reliable than crt.sh (which it replaced — crt.sh is a single
    # overloaded Postgres that frequently times out / 502s). Each issuance carries the cert's
    # validity window, so a subdomain's first_seen/last_seen = min(not_before)/max(not_after).
    class Certspotter < Provider
      def self.id            = "certspotter"
      def self.display_name  = "Certspotter"
      def self.requires_key? = false
      def self.record_types  = []

      PAGE_SIZE = 100
      MAX_PAGES = 5 # bounded; CT history for one domain is rarely deeper than this

      def fetch(domain, key: nil)
        d   = Normalize.host(domain)
        acc = {}
        after = nil
        # Certspotter pages by ?after=<last id>; keep going until an empty page (or the
        # MAX_PAGES bound), which is robust to whatever page size the server actually returns.
        MAX_PAGES.times do
          resp = http_get_json(page_url(d, after))
          raise_for_status(resp[:status], resp[:error]) unless resp[:status] == 200
          rows = resp[:body]
          break unless rows.is_a?(Array) && rows.any?
          merge_page(rows, d, acc)
          after = rows.last["id"]
          break if after.nil?
        end
        { records: [], subdomains: acc.values.sort_by { |h| h[:name] } }
      end

      private

      def page_url(domain, after)
        url = "https://api.certspotter.com/v1/issuances?domain=#{domain}" \
          "&include_subdomains=true&expand=dns_names&expand=not_before&expand=not_after&limit=#{PAGE_SIZE}"
        after ? "#{url}&after=#{after}" : url
      end

      def merge_page(rows, domain, acc)
        rows.each do |issuance|
          fseen = Normalize.date(issuance["not_before"])
          lseen = Normalize.date(issuance["not_after"])
          Array(issuance["dns_names"]).each do |raw|
            name = Normalize.host(raw)
            next if name.empty? || name.start_with?("*")
            next unless name == domain || name.end_with?(".#{domain}")
            e = (acc[name] ||= { name: name, first_seen: fseen, last_seen: lseen })
            e[:first_seen] = [e[:first_seen], fseen].compact.min
            e[:last_seen]  = [e[:last_seen], lseen].compact.max
          end
        end
      end
    end
  end
end
