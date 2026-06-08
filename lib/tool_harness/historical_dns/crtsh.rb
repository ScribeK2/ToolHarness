module ToolHarness
  module HistoricalDns
    # Certificate Transparency history (subdomains over time). No API key.
    class Crtsh < Provider
      def self.id            = "crtsh"
      def self.display_name  = "crt.sh"
      def self.requires_key? = false
      def self.record_types  = []
      # crt.sh is frequently slow (single overloaded Postgres). Give it room — it runs
      # concurrently with the other providers, so this doesn't lengthen the overall run.
      def self.read_timeout  = 20

      def fetch(domain, key: nil)
        d    = Normalize.host(domain)
        resp = http_get_json("https://crt.sh/?q=%25.#{d}&output=json")
        raise_for_status(resp[:status], resp[:error]) unless resp[:status] == 200
        rows = resp[:body]
        return { records: [], subdomains: [] } unless rows.is_a?(Array)
        { records: [], subdomains: parse_subdomains(rows, d) }
      end

      private

      def parse_subdomains(rows, domain)
        acc = {}
        rows.each do |row|
          fseen = Normalize.date(row["not_before"])
          lseen = Normalize.date(row["not_after"])
          row["name_value"].to_s.split("\n").each do |raw|
            name = Normalize.host(raw)
            next if name.empty? || name.start_with?("*")
            next unless name == domain || name.end_with?(".#{domain}")
            e = (acc[name] ||= { name: name, first_seen: fseen, last_seen: lseen })
            e[:first_seen] = [e[:first_seen], fseen].compact.min
            e[:last_seen]  = [e[:last_seen], lseen].compact.max
          end
        end
        acc.values.sort_by { |h| h[:name] }
      end
    end
  end
end
