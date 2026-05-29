module Investigations
  # Cross-probe synthesis over the three Orientation child runs. Produces ranked,
  # root-cause-first findings + a triage verdict. Reads result_data (string keys
  # after JSON round-trip) via with_indifferent_access so tests may use either.
  class OrientationCorrelator
    WEB_PORTS  = %w[http https].freeze
    MAIL_PORTS = %w[smtp smtps submission imap imaps pop3 pop3s].freeze

    def initialize(tool_runs)
      @runs = Array(tool_runs).index_by(&:tool_key)
    end

    def call
      findings = []
      findings.concat(expiry_findings)
      findings.concat(resolution_findings)
      findings.concat(ns_mismatch_findings)
      findings.concat(serving_findings)
      findings.concat(mail_findings)
      findings << healthy_finding if findings.empty?

      CorrelationResult.new(
        verdict_status: verdict_for(findings),
        findings: findings,
        suggested_track: suggested_track
      )
    end

    private

    def whois   = @runs["whois_lookup"]
    def dns     = @runs["dns_lookup"]
    def hosting = @runs["hosting_diagnostic"]

    def data(run) = (run&.result_data || {}).with_indifferent_access

    def open_ports = Array(data(hosting)[:open_ports]).map(&:to_s)
    def a_records  = Array(data(dns)[:a_records])
    def mx_records = Array(data(dns)[:mx_records])

    def expiry_findings
      exp = data(whois)[:expiration_date]
      return [] if exp.blank?
      days = days_until(exp)
      return [] if days.nil?

      if days.negative?
        [finding("critical", "domain_expired", "Domain expired",
                 "The domain expired #{days.abs} days ago — the likeliest root cause.",
                 %w[whois_lookup], "Renew immediately.")]
      elsif days <= 30
        [finding("warning", "domain_expiring", "Domain expiring soon",
                 "The domain expires in #{days} days.",
                 %w[whois_lookup], "Schedule renewal to avoid disruption.")]
      else
        []
      end
    end

    def resolution_findings
      return [] unless dns
      addressable = a_records.any? || Array(data(dns)[:aaaa_records]).any? || Array(data(dns)[:cname_records]).any?
      return [] if dns.success && addressable

      [finding("critical", "no_resolution", "Domain does not resolve",
               "No A/AAAA/CNAME records were returned.",
               %w[dns_lookup], "Check the zone's A record and that the nameservers are authoritative.")]
    end

    def ns_mismatch_findings
      return [] unless whois && dns
      reg  = Array(data(whois)[:nameservers]).map { |n| normalize_ns(n) }.reject(&:blank?).sort.uniq
      live = Array(data(dns)[:ns_records]).map  { |n| normalize_ns(n) }.reject(&:blank?).sort.uniq
      return [] if reg.empty? || live.empty? || reg == live

      [finding("warning", "ns_mismatch", "Nameserver mismatch",
               "Registrar lists #{reg.join(', ')} but DNS is answered by #{live.join(', ')}.",
               %w[whois_lookup dns_lookup],
               "Often normal mid-migration; if not migrating, align the registrar's nameservers with the live zone.")]
    end

    def serving_findings
      return [] unless dns&.success && hosting
      return [] if a_records.empty?
      return [] if (open_ports & WEB_PORTS).any?

      [finding("critical", "resolves_not_serving", "Resolves but nothing is serving the web",
               "#{a_records.first} is published, but neither HTTP (80) nor HTTPS (443) accepted a connection.",
               %w[dns_lookup hosting_diagnostic],
               "The site is down or the web server isn't listening — check the host/container.")]
    end

    def mail_findings
      return [] unless dns&.success
      if mx_records.empty?
        return [finding("warning", "no_mx", "Mail not configured",
                        "No MX records found — the domain cannot receive email.",
                        %w[dns_lookup], "Add MX records if this domain should receive mail.")]
      end
      return [] unless hosting
      return [] if (open_ports & MAIL_PORTS).any?

      [finding("warning", "mail_ports_closed", "MX present but mail not responding",
               "MX records exist, but no mail ports (25/465/587/993/995/110/143) accepted a connection.",
               %w[dns_lookup hosting_diagnostic],
               "The mail host may be down or firewalled — a black box beyond the panel.")]
    end

    def healthy_finding
      finding("info", "externally_healthy", "Externally healthy",
              "All orientation probes look healthy from outside. If the ticket persists, the cause is likely inside a black box (container internals / mail server / registry back-end).",
              %w[whois_lookup dns_lookup hosting_diagnostic],
              "Proceed to a deeper track, or escalate with this report if access is the blocker.")
    end

    def suggested_track
      return "email_delivery" if mx_records.any?
      return "hosting_website" if (open_ports & WEB_PORTS).any? || data(hosting)[:server_banner].present?
      nil
    end

    def verdict_for(findings)
      severities = findings.map { |f| f["severity"] }
      return "critical" if severities.include?("critical")
      return "issues"   if severities.include?("warning")
      "healthy"
    end

    def days_until(date_str)
      (Date.parse(date_str.to_s) - Date.today).to_i
    rescue ArgumentError, TypeError
      nil
    end

    def normalize_ns(value) = value.to_s.downcase.chomp(".")

    # String keys so the finding survives a JSON round-trip identically.
    def finding(severity, code, title, message, provenance, recommendation)
      {
        "severity" => severity, "code" => code, "title" => title,
        "message" => message, "provenance" => provenance, "recommendation" => recommendation
      }
    end
  end
end
