module Tools
  class HttpInspect
    include ToolHarness::Tool

    def self.tool_name = "HTTP & Security Headers"
    def self.category = :ssl
    def self.description = "Fetches the site over HTTP and HTTPS, follows redirects, evaluates security headers (HSTS, CSP, X-Frame-Options, etc.), and reports response time."
    def self.form_fields = { domain: :text }
    def self.input_type = :domain
    def self.cacheable? = false
    def self.preserve_path_in_input? = true

    def execute(params)
      raw = ::HttpChecker.check(params[:domain])

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
      return "HTTP check failed: #{raw[:error] || 'no response'}." unless raw[:success]

      https = raw[:https_response] || {}
      status = https[:status_code]
      rtime = https[:response_time_ms]

      parts = []
      parts << "HTTPS #{status} in #{rtime}ms" if status
      parts << (raw[:redirects_to_https] ? "HTTP→HTTPS redirect ok" : "no HTTP→HTTPS redirect")

      missing = raw[:missing_headers]&.size || 0
      parts << "#{missing} missing security header#{'s' if missing != 1}" if missing.positive?

      parts.any? ? "#{parts.join('. ')}." : "HTTPS reachable."
    end
  end
end
