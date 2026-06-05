module Tools
  class Ipinfo
    include ToolHarness::Tool

    def self.tool_name   = "IP Intelligence (IPinfo)"
    def self.category    = :diagnostics
    def self.description = "Looks up geolocation, ASN/org, company, and privacy (VPN/proxy/Tor/hosting) intel for an IP or hostname via IPinfo. Requires an API key (set in the Credentials tool)."
    def self.form_fields = { domain: :text }
    def self.input_type  = :host
    def self.cacheable?  = false
    def self.timeout     = 15

    def execute(params)
      token = ToolHarness::CredentialStore.new.secret_for("ipinfo")
      if token.to_s.empty?
        return ToolHarness::Result.new(
          success: false, tool: self.class.tool_name,
          error: "No IPinfo API key configured.",
          summary: "Add an IPinfo API key in the Credentials tool (id: ipinfo) to use this lookup."
        )
      end

      target = params[:domain].to_s.strip
      if ToolHarness::HostNormalizer.valid_ip?(target)
        ip, resolved_from = target, nil
      else
        ip = resolve(target)
        unless ip
          return ToolHarness::Result.new(
            success: false, tool: self.class.tool_name,
            error: "Could not resolve #{target} to an IPv4 address.",
            summary: "DNS resolution failed for #{target}."
          )
        end
        resolved_from = target
      end

      raw = ::IpinfoChecker.check(ip, token: token)
      unless raw[:success]
        return ToolHarness::Result.new(
          success: false, tool: self.class.tool_name,
          error: raw[:error], summary: "IPinfo lookup failed: #{raw[:error]}"
        )
      end

      ToolHarness::Result.new(
        success: true, tool: self.class.tool_name,
        data: build_data(raw, resolved_from),
        issues: build_issues(raw),
        summary: build_summary(raw, resolved_from)
      )
    end

    private

    def resolve(host)
      ::DnsChecker.check(host)[:a_records]&.first
    rescue StandardError
      nil
    end

    def build_data(raw, resolved_from)
      {
        ip: raw[:ip], hostname: raw[:hostname], resolved_from: resolved_from,
        city: raw[:city], region: raw[:region], country: raw[:country],
        loc: raw[:loc], postal: raw[:postal], timezone: raw[:timezone],
        asn: raw[:asn], org: raw[:org], company: raw[:company], privacy: raw[:privacy]
      }.compact
    end

    def build_issues(raw)
      p = raw[:privacy]
      return [] unless p.is_a?(Hash)
      flags = p.select { |_, v| v }.keys
      return [] if flags.empty?
      [{ "severity" => "info", "code" => "privacy_flagged",
         "title" => "IP flagged by IPinfo privacy detection",
         "message" => "Flags: #{flags.join(', ')}.",
         "recommendation" => "Common for VPN/proxy/hosting ranges; weigh in abuse triage." }]
    end

    def build_summary(raw, resolved_from)
      loc  = [raw[:city], raw[:country]].compact.join(", ")
      asn  = raw[:asn] ? "#{raw[:asn][:id]} #{raw[:asn][:name]}" : raw[:org]
      head = resolved_from ? "#{resolved_from} → #{raw[:ip]}" : raw[:ip]
      "#{[head, loc.presence, asn.presence].compact.join(' · ')}."
    end
  end
end
