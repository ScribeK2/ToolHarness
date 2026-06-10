module Investigations
  # Cross-probe synthesis over the email-delivery battery (dns_lookup, email_auth_check,
  # hosting_diagnostic, blacklist). Ranked, root-cause-first findings + a triage verdict.
  # Reads result_data via with_indifferent_access. Every probe is read defensively —
  # a skipped/failed probe simply contributes no finding.
  class EmailDeliveryCorrelator
    MAIL_PORTS       = %w[smtp smtps submission imap imaps pop3 pop3s].freeze
    # Listing on one of these (names as reported by Tools::Blacklist) is treated as
    # critical; any other DNSBL listing is a warning. Keep in sync with the list names
    # in app/services/tools/blacklist.rb if that battery changes.
    MAJOR_BLACKLISTS = ["Spamhaus ZEN", "Spamhaus DBL"].freeze

    def initialize(tool_runs)
      @runs = Array(tool_runs).index_by(&:tool_key)
    end

    def call
      findings = []
      findings.concat(mx_findings)
      findings.concat(smtp_findings)
      findings.concat(blacklist_findings)
      findings.concat(spf_findings)
      findings.concat(dkim_findings)
      findings.concat(dmarc_findings)
      findings << healthy_finding if findings.empty?

      CorrelationResult.new(
        verdict_status: verdict_for(findings),
        findings: findings,
        suggested_track: nil
      )
    end

    private

    def dns        = @runs["dns_lookup"]
    def email_auth = @runs["email_auth_check"]
    def hosting    = @runs["hosting_diagnostic"]
    def blacklist  = @runs["blacklist"]

    def data(run) = (run&.result_data || {}).with_indifferent_access

    # The merged email_auth_check run nests each record's raw checker output.
    def spf_data   = data(email_auth)[:spf]   || {}
    def dkim_data  = data(email_auth)[:dkim]  || {}
    def dmarc_data = data(email_auth)[:dmarc] || {}

    def mx_records = Array(data(dns)[:mx_records])
    def open_ports = Array(data(hosting)[:open_ports]).map(&:to_s)

    def mx_findings
      return [] unless dns&.success
      return [] if mx_records.any?
      [finding("critical", "no_mx", "No MX records — domain cannot receive mail",
               "DNS returned no MX records, so mail cannot be routed to this domain.",
               %w[dns_lookup], "Publish MX records pointing at the mail host.")]
    end

    def smtp_findings
      return [] unless dns&.success && hosting
      return [] if mx_records.empty?
      return [] if (open_ports & MAIL_PORTS).any?
      [finding("critical", "smtp_unreachable", "MX present but no mail ports answering",
               "The primary MX host (from DNS) accepted no connection on any mail port — SMTP/IMAP/POP3 (25/465/587/143/993/110/995) — from outside.",
               %w[dns_lookup hosting_diagnostic],
               "The mail host may be down or firewalled — escalate with Graylog Postfix/Dovecot logs if it should be up.")]
    end

    def blacklist_findings
      listings = Array(data(blacklist)[:listings])
      return [] if listings.empty?
      names = listings.map { |l| l.is_a?(Hash) ? (l["name"] || l[:name]) : l }.compact
      sev   = (names & MAJOR_BLACKLISTS).any? ? "critical" : "warning"
      [finding(sev, "mail_blacklisted", "Mail server is blacklisted",
               "The mail host is listed on: #{names.join(', ')}. Recipients likely reject or spam-folder its mail.",
               %w[blacklist dns_lookup],
               "Request delisting from the listing services and confirm the host isn't sending spam.")]
    end

    def spf_findings
      return [] unless email_auth
      if issue_codes(email_auth).include?("too_many_lookups")
        return [finding("critical", "spf_permerror", "SPF exceeds the 10-lookup limit",
                        "The SPF record requires more than 10 DNS lookups (a permerror) — receivers treat SPF as broken.",
                        %w[email_auth_check], "Flatten includes to get under 10 DNS lookups.")]
      end
      unless spf_data[:success]
        return [finding("warning", "spf_missing", "No SPF record",
                        "No SPF record was found; receivers can't verify which hosts may send for this domain.",
                        %w[email_auth_check], "Publish an SPF record ending in -all or ~all.")]
      end
      all = spf_data[:all_mechanism]
      qual = all.is_a?(Hash) ? all[:qualifier] : nil
      if qual.nil? || qual == "+"
        return [finding("warning", "spf_permissive", "SPF has no restrictive all mechanism",
                        "The SPF record has no -all/~all (or uses +all), so it does not constrain senders.",
                        %w[email_auth_check], "End the SPF record with ~all or -all.")]
      end
      []
    end

    def dkim_findings
      return [] unless email_auth
      selectors = Array(dkim_data[:selectors_found])
      if selectors.empty?
        return [finding("warning", "dkim_absent", "No DKIM signature found",
                        "No common DKIM selector answered. NOTE: the probe checks only common selectors, so a custom selector cannot be ruled out from outside.",
                        %w[email_auth_check], "Confirm DKIM signing is configured; if it uses a custom selector, verify it directly.")]
      end
      testing = selectors.any? { |s| s.is_a?(Hash) && s.dig("parsed", "flags").to_s.include?("y") }
      if testing
        return [finding("warning", "dkim_testing", "DKIM is in testing mode",
                        "A DKIM selector carries the t=y testing flag, so receivers ignore DKIM failures.",
                        %w[email_auth_check], "Remove t=y once DKIM is verified working.")]
      end
      []
    end

    def dmarc_findings
      return [] unless email_auth
      unless dmarc_data[:success]
        return [finding("warning", "dmarc_missing", "No DMARC record",
                        "No DMARC record was found; the domain is spoofable and has no reporting.",
                        %w[email_auth_check], "Publish a _dmarc record (start at p=none with rua reporting, then tighten).")]
      end
      if dmarc_data[:policy].to_s == "none"
        return [finding("warning", "dmarc_policy_none", "DMARC policy is p=none",
                        "DMARC is published but the policy is none, so failing mail is neither quarantined nor rejected.",
                        %w[email_auth_check], "Move to p=quarantine then p=reject after monitoring reports.")]
      end
      []
    end

    def healthy_finding
      finding("info", "mail_externally_healthy", "Mail infrastructure externally healthy",
              "MX routes, mail ports answer, SPF/DKIM/DMARC are present and sane, and the mail host is not blacklisted. If mail is still failing, the cause is inside the mail server — escalate with Graylog Postfix/Dovecot logs.",
              %w[dns_lookup email_auth_check hosting_diagnostic blacklist],
              "Escalate to Tier 3 with this report and the relevant Graylog log lines.")
    end

    def issue_codes(run) = Array(run&.issues).map { |i| (i.is_a?(Hash) ? (i["code"] || i[:code]) : i).to_s }

    def verdict_for(findings)
      sev = findings.map { |f| f["severity"] }
      return "critical" if sev.include?("critical")
      return "issues"   if sev.include?("warning")
      "healthy"
    end

    def finding(severity, code, title, message, provenance, recommendation)
      {
        "severity" => severity, "code" => code, "title" => title,
        "message" => message, "provenance" => provenance, "recommendation" => recommendation
      }
    end
  end
end
