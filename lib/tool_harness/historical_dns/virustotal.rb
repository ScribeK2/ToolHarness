module ToolHarness
  module HistoricalDns
    # VirusTotal v3 passive-DNS resolutions (A/AAAA observed over time). Free API key.
    class Virustotal < Provider
      def self.id            = "virustotal"
      def self.display_name  = "VirusTotal"
      def self.requires_key? = true
      def self.record_types  = %i[a aaaa]

      MAX_PAGES = 3

      def fetch(domain, key:)
        d   = Normalize.host(domain)
        url = "https://www.virustotal.com/api/v3/domains/#{d}/resolutions?limit=40"
        records = []
        pages   = 0
        while url && pages < MAX_PAGES
          resp = http_get_json(url, { "x-apikey" => key.to_s })
          raise_for_status(resp[:status], resp[:error]) unless resp[:status] == 200
          body = resp[:body]
          break unless body.is_a?(Hash)
          Array(body["data"]).each do |item|
            ip = (item["attributes"] || {})["ip_address"].to_s
            next if ip.empty?
            seen = Normalize.date((item["attributes"] || {})["date"])
            type = ip.include?(":") ? :aaaa : :a
            records << Record.new(type: type, value: ip, first_seen: seen, last_seen: seen, sources: [self.class.id])
          end
          url = body.dig("links", "next")
          pages += 1
        end
        { records: records, subdomains: [] }
      end
    end
  end
end
