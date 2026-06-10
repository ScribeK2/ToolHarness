require "resolv"

module ToolHarness
  module HistoricalDns
    # Current-state DNS snapshot via Ruby's stdlib resolver (no host deps — fits the
    # AppImage rule). This is the only *free* source for NS/MX/SOA, which passive-DNS
    # providers never observe. It can't show history, so its records are dated "today"
    # (first_seen == last_seen); the Aggregator marks them current, anchoring the timeline's
    # present so a customer's current nameservers/mail are always visible. Pair with
    # Whoisfreaks (paid) when full NS/MX *history* is needed.
    class Livedns < Provider
      def self.id            = "livedns"
      def self.display_name  = "Live DNS"
      def self.requires_key? = false
      def self.record_types  = %i[a aaaa ns mx txt soa cname]

      # Resolv query timeout (seconds). Short — this runs concurrently with the other
      # providers and the orchestrator caps the whole phase anyway.
      RESOLVE_TIMEOUT = 4

      def fetch(domain, key: nil)
        d    = Normalize.host(domain)
        snap = resolve_all(d)
        today = Date.today
        records = []
        records.concat(snap[:a].to_a.map    { |v| rec(:a,    v.to_s.strip,        today) })
        records.concat(snap[:aaaa].to_a.map { |v| rec(:aaaa, v.to_s.strip,        today) })
        records.concat(snap[:ns].to_a.map   { |v| rec(:ns,   Normalize.host(v),   today) })
        records.concat(snap[:cname].to_a.map { |v| rec(:cname, Normalize.host(v), today) })
        records.concat(snap[:soa].to_a.map  { |v| rec(:soa,  Normalize.host(v),   today) })
        records.concat(snap[:txt].to_a.map  { |v| rec(:txt,  Normalize.text(v),   today) })
        records.concat(snap[:mx].to_a.map   { |(pri, ex)| rec(:mx, Normalize.mx(pri, ex), today) })
        { records: records.reject { |r| r.value.empty? }, subdomains: [] }
      rescue Resolv::ResolvError, Resolv::ResolvTimeout, IOError, SystemCallError => e
        raise ProviderError.new(:unavailable, "Live DNS resolution failed: #{e.message}")
      end

      private

      def rec(type, value, date)
        Record.new(type: type, value: value, first_seen: date, last_seen: date, sources: [self.class.id])
      end

      # Live resolution seam (stubbed in tests). Returns the current records per type.
      def resolve_all(domain)
        dns = Resolv::DNS.new
        dns.timeouts = RESOLVE_TIMEOUT
        {
          a:     dns.getresources(domain, Resolv::DNS::Resource::IN::A).map    { |r| r.address.to_s },
          aaaa:  dns.getresources(domain, Resolv::DNS::Resource::IN::AAAA).map { |r| r.address.to_s },
          ns:    dns.getresources(domain, Resolv::DNS::Resource::IN::NS).map   { |r| r.name.to_s },
          mx:    dns.getresources(domain, Resolv::DNS::Resource::IN::MX).map   { |r| [r.preference, r.exchange.to_s] },
          txt:   dns.getresources(domain, Resolv::DNS::Resource::IN::TXT).map  { |r| r.strings.join },
          soa:   dns.getresources(domain, Resolv::DNS::Resource::IN::SOA).map  { |r| r.mname.to_s },
          cname: dns.getresources(domain, Resolv::DNS::Resource::IN::CNAME).map { |r| r.name.to_s }
        }
      ensure
        dns&.close
      end
    end
  end
end
