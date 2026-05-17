require "dnsruby"
require "ipaddr"

module Tools
  class Blacklist
    include ToolHarness::Tool

    IP_DNSBLS = {
      "Spamhaus ZEN" => "zen.spamhaus.org",
      "Barracuda"    => "b.barracudacentral.org",
      "SpamCop"      => "bl.spamcop.net",
      "SORBS"        => "dnsbl.sorbs.net",
      "PSBL"         => "psbl.surriel.com",
      "Manitu IX"    => "ix.dnsbl.manitu.net"
    }.freeze

    DOMAIN_DNSBLS = {
      "Spamhaus DBL" => "dbl.spamhaus.org",
      "SURBL"        => "multi.surbl.org"
    }.freeze

    QUERY_TIMEOUT_S = 4

    def self.tool_name = "Blacklist Check"
    def self.category = :diagnostics
    def self.description = "Queries #{IP_DNSBLS.size + DOMAIN_DNSBLS.size} DNS-based blacklists in parallel (Spamhaus, Barracuda, SpamCop, SORBS, PSBL, Manitu for IPs; Spamhaus DBL and SURBL for domains). For domain input, also resolves to the primary A record and checks that IP."
    def self.form_fields = { domain: :text }
    def self.input_type = :host
    def self.cacheable? = false
    def self.timeout = 20

    def execute(params)
      target = params[:domain].to_s.strip

      unless valid_target?(target)
        return ToolHarness::Result.new(
          success: false, tool: self.class.tool_name,
          error: "Invalid target: must be a domain name or IPv4 address.",
          summary: "Invalid input"
        )
      end

      target_is_ip = valid_ipv4?(target)
      ip_to_check  = target_is_ip ? target : resolve_to_ipv4(target)

      lookups = []
      if ip_to_check
        IP_DNSBLS.each do |name, zone|
          lookups << { kind: :ip, name: name, zone: zone, query_for: ip_to_check, q: "#{reverse_octets(ip_to_check)}.#{zone}" }
        end
      end
      unless target_is_ip
        DOMAIN_DNSBLS.each do |name, zone|
          lookups << { kind: :domain, name: name, zone: zone, query_for: target, q: "#{target}.#{zone}" }
        end
      end

      if lookups.empty?
        return ToolHarness::Result.new(
          success: false, tool: self.class.tool_name,
          error: "No DNSBL queries possible — could not resolve target to an IPv4 address.",
          summary: "DNS resolution failed for #{target}"
        )
      end

      results = run_lookups_parallel(lookups)

      listed   = results.select { |r| r[:listed] }
      clean    = results.select { |r| !r[:listed] && r[:error].nil? }
      errored  = results.select { |r| r[:error] }

      ToolHarness::Result.new(
        success: true,
        tool: self.class.tool_name,
        data: {
          target:        target,
          ip_checked:    ip_to_check,
          listings:      listed,
          clean:         clean.map { |r| r[:name] },
          errors:        errored.map { |r| { name: r[:name], error: r[:error] } },
          total_checked: results.size
        },
        issues:  build_issues(listed, errored),
        summary: build_summary(target, ip_to_check, listed, results.size)
      )
    end

    private

    def valid_target?(s)
      return false if s.empty? || s.size > 253
      return true if valid_ipv4?(s)
      s.match?(/\A[a-zA-Z0-9](?:[a-zA-Z0-9\-]*[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9\-]*[a-zA-Z0-9])?)+\z/)
    end

    def valid_ipv4?(s)
      addr = IPAddr.new(s)
      addr.ipv4?
    rescue IPAddr::InvalidAddressError
      false
    end

    def reverse_octets(ip)
      ip.split(".").reverse.join(".")
    end

    def resolve_to_ipv4(domain)
      dns = ::DnsChecker.check(domain)
      ip  = dns[:a_records]&.first
      valid_ipv4?(ip) ? ip : nil
    rescue StandardError
      nil
    end

    def run_lookups_parallel(lookups)
      lookups.map { |l| Thread.new { query_dnsbl(l) } }.map(&:value)
    end

    def query_dnsbl(lookup)
      # System resolver (no nameserver: arg) avoids Spamhaus' public-resolver blocks.
      resolver = Dnsruby::Resolver.new(timeout: QUERY_TIMEOUT_S)
      out = {
        name:      lookup[:name],
        zone:      lookup[:zone],
        kind:      lookup[:kind],
        target:    lookup[:query_for],
        query:     lookup[:q],
        listed:    false
      }

      begin
        response = resolver.query(lookup[:q], Dnsruby::Types::A)
        codes    = response.answer.select { |r| r.type == Dnsruby::Types::A }.map { |r| r.address.to_s }
        if codes.any?
          out[:listed]       = true
          out[:return_codes] = codes
          out[:reason]       = fetch_txt(resolver, lookup[:q]).first
        end
      rescue Dnsruby::NXDomain
        out[:listed] = false  # explicit "not listed"
      rescue StandardError => e
        # dnsruby 1.73 raises a variety of error classes (ServFail, Timeout-ish,
        # network errors) — match by name. Spamhaus/Barracuda often return
        # SERVFAIL when queried via large public resolvers (rate limits /
        # commercial-use policy). Treat any non-NXDOMAIN failure as "errored,
        # not a clean signal."
        out[:error] = "#{e.class.name.split('::').last}: #{e.message}"
      end

      out
    end

    def fetch_txt(resolver, name)
      resp = resolver.query(name, Dnsruby::Types::TXT)
      resp.answer.select { |r| r.type == Dnsruby::Types::TXT }.map { |r| r.strings.join }
    rescue StandardError
      []
    end

    def build_issues(listed, errored)
      issues = []

      listed.each do |entry|
        reason = entry[:reason].present? ? " — #{entry[:reason]}" : ""
        issues << {
          severity:       "critical",
          code:           "listed_on_#{entry[:name].downcase.tr(' ', '_')}",
          title:          "Listed on #{entry[:name]}",
          message:        "#{entry[:target]} is listed on #{entry[:zone]} (return code #{entry[:return_codes].join(', ')})#{reason}.",
          recommendation: "Review the listing on #{entry[:zone]} and request delisting if appropriate."
        }
      end

      if errored.any?
        issues << {
          severity:       "info",
          code:           "dnsbl_query_errors",
          title:          "Some DNSBL queries failed",
          message:        "#{errored.size} of the configured DNSBLs did not respond cleanly: #{errored.map { |e| e[:name] }.join(', ')}.",
          recommendation: "Likely a transient resolver issue or rate-limit. Retry for a complete picture."
        }
      end

      issues
    end

    def build_summary(target, ip, listed, total)
      base = (ip && ip != target) ? "#{target} (#{ip})" : target.to_s
      if listed.empty?
        "#{base}: not listed on any of #{total} DNSBLs checked."
      else
        names = listed.map { |l| l[:name] }.join(", ")
        "#{base}: LISTED on #{listed.size} of #{total} DNSBLs (#{names})."
      end
    end
  end
end
