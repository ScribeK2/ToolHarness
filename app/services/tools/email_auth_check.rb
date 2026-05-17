module Tools
  class EmailAuthCheck
    include ToolHarness::Tool

    def self.tool_name = "Email Authentication Overview"
    def self.category = :email_auth
    def self.description = "Runs SPF, DKIM, and DMARC checks together, computes an authentication grade (A–F), and surfaces cross-record issues such as MX without SPF or DMARC reject with permissive SPF."
    def self.form_fields = { domain: :text }
    def self.input_type = :domain
    def self.cacheable? = false
    def self.timeout = 90

    def execute(params)
      domain = params[:domain]

      # Pull MX records (cached) so the "MX without SPF" cross-issue check fires correctly.
      dns_raw = ::DnsChecker.check(domain)
      mx_records = dns_raw[:success] ? dns_raw[:mx_records] : nil

      raw = ::EmailChecker.check(domain, mx_records: mx_records)

      ToolHarness::Result.new(
        success: raw[:success],
        tool: self.class.tool_name,
        data: raw.except(:issues, :success, :recommendations),
        issues: raw[:issues] || [],
        recommendations: raw[:recommendations] || [],
        summary: build_summary(raw),
        error: raw[:error]
      )
    end

    private

    def build_summary(raw)
      return "Email auth check failed: #{raw[:error] || 'unknown error'}." unless raw[:success]

      grade = raw[:authentication_grade]
      score = raw[:authentication_score]

      spf_ok   = raw[:spf]&.dig(:success)
      dkim_ok  = raw[:dkim]&.dig(:success) && raw[:dkim][:selectors_found].present?
      dmarc_ok = raw[:dmarc]&.dig(:success)

      parts = []
      parts << (spf_ok  ? "SPF set" : "no SPF")
      parts << (dkim_ok ? "DKIM set" : "no DKIM")
      parts << if dmarc_ok
        "DMARC set (p=#{raw[:dmarc][:policy]})"
      else
        "no DMARC"
      end

      "Email auth grade #{grade} (#{score}/100): #{parts.join(', ')}."
    end
  end
end
