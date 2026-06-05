module Investigations
  # Correlates the hosting_website battery (dns_lookup, hosting_diagnostic,
  # http_inspect, ssl_inspect, website_health) into a hosting/website verdict.
  class HostingWebsiteCorrelator
    WEB_PORTS = %w[http https].freeze
    DB_PORTS  = %w[mysql postgresql redis mongodb].freeze

    def initialize(tool_runs)
      @runs = Array(tool_runs).index_by(&:tool_key)
    end

    def call
      findings = []
      findings.concat(resolution_findings)
      findings.concat(reachability_findings)
      findings.concat(serving_findings)
      findings.concat(ssl_findings)
      findings.concat(maintenance_findings)
      findings.concat(client_error_findings)
      findings.concat(redirect_findings)
      findings.concat(db_exposure_findings)
      findings.concat(header_findings)
      findings << healthy_finding if findings.empty?

      CorrelationResult.new(
        verdict_status: verdict_for(findings),
        findings: findings,
        suggested_track: nil
      )
    end

    private

    def dns     = @runs["dns_lookup"]
    def hosting = @runs["hosting_diagnostic"]
    def http    = @runs["http_inspect"]
    def ssl     = @runs["ssl_inspect"]
    def web     = @runs["website_health"]

    def data(run)  = (run&.result_data || {}).with_indifferent_access
    def a_records  = Array(data(dns)[:a_records])
    def open_ports = Array(data(hosting)[:open_ports]).map(&:to_s)
    def web_health = data(web)[:health].to_s

    def resolution_findings
      return [] unless dns&.success
      addressable = a_records.any? || Array(data(dns)[:aaaa_records]).any? || Array(data(dns)[:cname_records]).any?
      return [] if addressable
      [finding("critical", "no_resolution", "Domain does not resolve",
               "No A/AAAA/CNAME records were returned.",
               %w[dns_lookup], "Check the zone's A record and that the nameservers are authoritative.")]
    end

    def reachability_findings
      return [] unless web
      if web_health == "unreachable"
        return [finding("critical", "site_unreachable", "Site unreachable",
                        "The homepage did not respond over HTTPS or HTTP.",
                        %w[website_health], "Confirm the web server/container is running and listening.")]
      end
      out = []
      if %w[server_error down].include?(web_health)
        out << finding("critical", "site_server_error", "Site returns a server error",
                       "The homepage responded with HTTP #{data(web)[:status_code]} — a server-side failure.",
                       %w[website_health], "Check the web server and application/PHP error logs inside the container.")
      end
      if data(web)[:critical_error]
        wp = data(web)[:wp_version].presence
        out << finding("critical", "wp_critical_error", "WordPress critical error",
                       "WordPress is showing its critical-error page#{wp ? " (WordPress #{wp})" : ''} — a fatal PHP error, usually a plugin/theme or memory issue.",
                       %w[website_health], "Check wp-content/debug.log and recently changed plugins/themes; enable WP_DEBUG inside the container.")
      end
      out
    end

    def serving_findings
      return [] unless dns&.success && hosting
      return [] if a_records.empty?
      return [] if (open_ports & WEB_PORTS).any?
      [finding("critical", "resolves_not_serving", "Resolves but nothing is serving the web",
               "#{a_records.first} is published, but neither HTTP (80) nor HTTPS (443) accepted a connection.",
               %w[dns_lookup hosting_diagnostic], "The site is down or the web server isn't listening — check the host/container.")]
    end

    def ssl_findings
      return [] unless ssl&.success
      out  = []
      days = data(ssl).dig(:certificate, :days_until_expiry)
      unless days.nil?
        days = days.to_i
        if days.negative?
          out << finding("critical", "ssl_expired", "TLS certificate expired",
                         "The certificate expired #{days.abs} days ago — browsers will block the site.",
                         %w[ssl_inspect], "Renew/reissue the certificate immediately.")
        elsif days <= 14
          out << finding("warning", "ssl_expiring", "TLS certificate expiring soon",
                         "The certificate expires in #{days} days.",
                         %w[ssl_inspect], "Renew before expiry to avoid an outage.")
        end
      end
      if Array(data(ssl)[:deprecated_protocols]).any?
        out << finding("warning", "deprecated_tls", "Deprecated TLS protocols enabled",
                       "The server still negotiates #{Array(data(ssl)[:deprecated_protocols]).join(', ')}.",
                       %w[ssl_inspect], "Disable TLS 1.0/1.1 on the web server.")
      end
      out
    end

    def maintenance_findings
      return [] unless web && data(web)[:maintenance_mode]
      [finding("warning", "maintenance_mode", "Site in maintenance mode",
               "WordPress is showing the 'briefly unavailable for scheduled maintenance' page — often a stuck update.",
               %w[website_health], "Remove the .maintenance file from the WordPress root inside the container.")]
    end

    def client_error_findings
      return [] unless web && web_health == "client_error"
      [finding("warning", "site_client_error", "Homepage returns a client error",
               "The homepage responded with HTTP #{data(web)[:status_code]} (e.g. 403/404).",
               %w[website_health], "Check access rules / document root / index file on the host.")]
    end

    def redirect_findings
      return [] unless http&.success
      return [] if data(http)[:redirects_to_https]
      http_resp = data(http)[:http_response]
      return [] unless http_resp.is_a?(Hash) && http_resp[:success]
      [finding("warning", "no_https_redirect", "HTTP does not redirect to HTTPS",
               "Plain HTTP requests are not redirected to HTTPS.",
               %w[http_inspect], "Add a 301 redirect from HTTP to HTTPS.")]
    end

    def db_exposure_findings
      return [] unless hosting&.success
      exposed = open_ports & DB_PORTS
      return [] if exposed.empty?
      [finding("warning", "database_port_exposed", "Database port reachable from outside",
               "Public connections were accepted on: #{exposed.join(', ')}.",
               %w[hosting_diagnostic], "Firewall database ports to internal traffic only.")]
    end

    def header_findings
      return [] unless http&.success
      missing = Array(data(http)[:missing_headers])
      return [] if missing.empty?
      [finding("info", "missing_security_headers", "Missing security headers",
               "The site is missing: #{missing.join(', ')}.",
               %w[http_inspect], "Add the missing headers (HSTS, CSP, X-Frame-Options, etc.).")]
    end

    def healthy_finding
      wp = data(web)[:is_wordpress] ? " WordPress#{data(web)[:wp_version].present? ? " #{data(web)[:wp_version]}" : ''} detected and" : ""
      finding("info", "site_externally_healthy", "Site externally healthy",
              "Domain resolves, the web server is serving, HTTPS works with a valid certificate, and the homepage returns OK.#{wp} If the site is still misbehaving, the cause is inside the container/app layer (PHP error log, plugin/theme, or database) — escalate with Pterodactyl/container logs.",
              %w[dns_lookup hosting_diagnostic http_inspect ssl_inspect website_health],
              "Escalate to Tier 3 with this report and the relevant container/PHP error logs.")
    end

    def verdict_for(findings)
      sev = findings.map { |f| f["severity"] }
      return "critical" if sev.include?("critical")
      return "issues"   if sev.include?("warning")
      "healthy"
    end

    def finding(severity, code, title, message, provenance, recommendation)
      { "severity" => severity, "code" => code, "title" => title,
        "message" => message, "provenance" => provenance, "recommendation" => recommendation }
    end
  end
end
