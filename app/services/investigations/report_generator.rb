module Investigations
  # Rolls a completed investigation into a paste-ready markdown report for the
  # Tier-3 internal ticket comment. The visibility-boundary section names which
  # black boxes the rep could not see past.
  class ReportGenerator
    def initialize(investigation)
      @inv = investigation
    end

    def to_markdown
      [header, findings_section, boundary_section, evidence_section].join("\n\n")
    end

    private

    def header
      lines = ["# Investigation — #{@inv.domain}"]
      lines << "- **Track:** #{@inv.track}"
      lines << "- **Ticket:** #{@inv.ticket_ref}" if @inv.ticket_ref.present?
      lines << "- **Verdict:** #{@inv.verdict_status.to_s.upcase}"
      lines << "- **Completed:** #{@inv.completed_at&.iso8601}"
      lines.join("\n")
    end

    def findings_section
      lines = ["## Findings"]
      if @inv.findings.blank?
        lines << "_No findings recorded._"
      else
        @inv.findings.each do |f|
          lines << "- **[#{f['severity'].to_s.upcase}] #{f['title']}** — #{f['message']} _(#{Array(f['provenance']).join(', ')})_"
          lines << "  - ↳ #{f['recommendation']}" if f["recommendation"].present?
        end
      end
      lines.join("\n")
    end

    def boundary_section
      boxes = ["registry back-end (gated — only some reps have registry access)"]
      codes = @inv.findings.map { |f| f["code"] }
      hosting_codes = %w[resolves_not_serving site_server_error site_unreachable wp_critical_error maintenance_mode ssl_expired]
      if @inv.track == "hosting_website" || codes.intersect?(hosting_codes)
        boxes << "Pterodactyl container internals (panel only — no container/sudo access)"
      end
      if codes.intersect?(%w[site_server_error wp_critical_error])
        boxes << "application/PHP layer inside the container (error logs, plugin/theme/DB state — not visible from outside)"
      end
      # Codes from BOTH correlators: orientation emits no_mx/mail_ports_closed, the
      # email track emits the rest. Listed together so an orientation investigation that
      # surfaces a mail issue still names the mail-server box, not only email_delivery runs.
      mail_codes = %w[no_mx mail_ports_closed smtp_unreachable mail_blacklisted spf_permerror dmarc_missing]
      if @inv.track == "email_delivery" || codes.intersect?(mail_codes)
        boxes << "mail server internals (only Postfix/Dovecot logs via Graylog — no DB)"
      end

      [
        "## Visibility boundary",
        "Everything above is observed from **outside**. Could not observe (black box):",
        boxes.map { |b| "- #{b}" }.join("\n"),
        "If resolution needs access to any of the above, escalate with this report."
      ].join("\n")
    end

    def evidence_section
      lines = ["## Probe evidence"]
      @inv.tool_runs.each do |run|
        status = case run.status
        when "failed"  then "FAILED"
        when "skipped" then "SKIPPED"
        else                "ok"
        end
        lines << "### #{run.tool_name} (#{status})"
        lines << (run.summary.presence || run.skip_reason.presence || "_no summary_")
      end
      lines.join("\n")
    end
  end
end
