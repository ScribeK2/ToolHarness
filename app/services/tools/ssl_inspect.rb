module Tools
  class SslInspect
    include ToolHarness::Tool

    def self.tool_name = "SSL/TLS Inspection"
    def self.category = :web
    def self.description = "Connects to the host, parses the certificate chain, probes supported TLS versions, and flags expiration, weak keys, and deprecated protocols."
    def self.form_fields = { domain: :text, port: :number }
    def self.input_type = :domain
    def self.cacheable? = false

    def execute(params)
      port = (params[:port].presence || 443).to_i
      raw = ::SslChecker.check(params[:domain], port: port)

      ToolHarness::Result.new(
        success: raw[:success],
        tool: self.class.tool_name,
        data: raw.except(:issues, :success),
        issues: raw[:issues] || [],
        summary: build_summary(raw),
        error: raw[:error]
      )
    end

    private

    def build_summary(raw)
      return "SSL check failed: #{raw[:error] || 'unknown error'}." unless raw[:success]

      cert = raw[:certificate]
      return "SSL connected but no certificate parsed." unless cert

      days = cert[:days_until_expiry]
      expiry = days.to_i.negative? ? "expired #{days.abs}d ago" : "expires in #{days}d"

      protocols = raw[:supported_protocols] || []
      protocol_str = protocols.any? ? " (#{protocols.join(', ')})" : ""

      cn = cert[:common_name].presence || raw[:domain]
      deprecated = raw[:deprecated_protocols] || []
      warn = deprecated.any? ? " Deprecated: #{deprecated.join(', ')}." : ""

      "Certificate for #{cn} #{expiry}#{protocol_str}.#{warn}"
    end
  end
end
