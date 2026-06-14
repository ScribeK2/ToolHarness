module Tools
  class EmailHeaderAnalyzer
    include ToolHarness::Tool

    def self.tool_name  = "Email Header Analyzer"
    def self.category   = :email
    def self.description = "Paste raw message headers to reconstruct the delivery path (hops, delays, originating IP), read the receiving server's actual SPF/DKIM/DMARC verdicts, flag From/Return-Path/Reply-To spoofing signals, and pivot the originating IP through RDAP / blacklist / IPinfo."
    def self.form_fields = { headers: :textarea }
    def self.input_type  = :email
    def self.cacheable?  = false
    def self.timeout     = 20
    def self.result_partial = "results/tools/email_header_analyzer"

    def execute(params)
      raw = params[:headers].to_s
      parsed = EmailHeaderParser.new(raw).analyze

      unless parsed[:ok]
        return ToolHarness::Result.new(
          success: false, tool: self.class.tool_name,
          error: "No email headers detected.",
          summary: "Paste the raw message headers (From:, Received:, Authentication-Results:, …)."
        )
      end

      origin = origin_block(parsed)

      ToolHarness::Result.new(
        success: true,
        tool: self.class.tool_name,
        data: {
          timeline:  parsed[:timeline],
          auth:      parsed[:auth],
          alignment: parsed[:alignment],
          headers:   parsed[:headers].slice("from", "return-path", "reply-to", "message-id", "subject", "date"),
          origin:    origin
        },
        issues:  build_issues(parsed, origin),
        summary: build_summary(parsed)
      )
    end

    private

    def origin_block(parsed)
      ip = parsed[:origin_ip]
      return { ip: nil } unless ip

      {
        ip: ip,
        rdap_name: rdap_name(ip),
        blacklist_listings: blacklist_listings(ip),
        ipinfo: ipinfo_block(ip)
      }
    end

    def rdap_name(ip)
      r = RdapChecker.check(ip)
      return nil unless r && r[:success]
      raw = r[:raw_data] || {}
      raw["name"] || raw["handle"]
    rescue StandardError
      nil
    end

    def blacklist_listings(ip)
      res = Tools::Blacklist.new.execute(domain: ip)
      (res.data[:listings] || []).map { |l| l[:name] || l["name"] }.compact
    rescue StandardError
      []
    end

    def ipinfo_block(ip)
      token = ToolHarness::CredentialStore.new.secret_for("ipinfo")
      return nil if token.blank?
      raw = IpinfoChecker.check(ip, token: token)
      return nil unless raw && raw[:success]
      { asn: raw[:asn], org: raw[:org], city: raw[:city], country: raw[:country], privacy: raw[:privacy] }
    rescue StandardError
      nil
    end

    def build_issues(parsed, origin)
      issues = []

      if origin && origin[:blacklist_listings].present?
        issues << { "severity" => "warning",
                    "title" => "Originating IP is blacklisted (#{origin[:blacklist_listings].size})",
                    "message" => "#{origin[:ip]} listed on: #{origin[:blacklist_listings].join(', ')}." }
      end

      auth = parsed[:auth]
      %i[spf dkim dmarc].each do |m|
        next unless auth[m] == "fail"
        sev = (m == :dmarc) ? "critical" : "warning"
        issues << { "severity" => sev, "title" => "#{m.upcase} failed at the receiving server",
                    "message" => "Authentication-Results reported #{m}=fail." }
      end

      al = parsed[:alignment]
      misaligned = al[:from_return_path_aligned] == false || al[:message_id_aligned] == false
      auth_failed = auth[:dmarc] == "fail" || auth[:spf] == "fail"
      if misaligned && auth_failed
        issues << { "severity" => "critical", "title" => "Possible spoofing: identity misalignment + failed auth",
                    "message" => "From (#{al[:from_domain]}) does not align with Return-Path (#{al[:return_path_domain]}) / Message-ID and authentication failed." }
      elsif misaligned
        issues << { "severity" => "info", "title" => "Identity domains do not align",
                    "message" => "From #{al[:from_domain]} vs Return-Path #{al[:return_path_domain]}. Legitimate senders sometimes misalign; weigh with the auth verdicts." }
      end

      if (skew = al[:date_skew_s]) && skew > 86_400
        issues << { "severity" => "info", "title" => "Large Date vs first-hop skew",
                    "message" => "#{(skew / 3600).round}h between the Date header and the first relay timestamp." }
      end

      parsed[:timeline][:hops].select { |h| h[:delay_s] && h[:delay_s] > 300 }.each do |h|
        issues << { "severity" => "info", "title" => "Slow relay hop (#{(h[:delay_s] / 60).round}m)",
                    "message" => "Hop #{h[:index]} via #{h[:by_host]} took #{(h[:delay_s] / 60).round} minutes." }
      end

      issues
    end

    def build_summary(parsed)
      auth = parsed[:auth]
      verdicts = %i[spf dkim dmarc].map { |m| "#{m}=#{auth[m] || '—'}" }.join(" ")
      hops = parsed[:timeline][:hops].size
      origin = parsed[:origin_ip] ? " from #{parsed[:origin_ip]}" : ""
      "#{hops} hop#{'s' unless hops == 1}#{origin}. Auth: #{verdicts}."
    end
  end
end
