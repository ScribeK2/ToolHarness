module Tools
  class WebsiteInspect
    include ToolHarness::Tool

    def self.tool_name = "Website Inspection"
    def self.category = :hosting
    def self.description = "One pass over the site: HTTP health classification, redirect behavior, security headers (HSTS, CSP, X-Frame-Options, etc.), and WordPress detection including critical-error and maintenance states."
    def self.form_fields = { domain: :text }
    def self.input_type = :domain
    def self.cacheable? = false
    def self.timeout = 20
    def self.preserve_path_in_input? = true

    def execute(params)
      raw = ::WebsiteInspector.check(params[:domain])

      ToolHarness::Result.new(
        success: raw[:success],
        tool: self.class.tool_name,
        data: raw.except(:issues, :success, :error),
        issues: raw[:issues] || [],
        summary: build_summary(raw),
        error: raw[:error]
      )
    end

    private

    def build_summary(raw)
      return "Site unreachable over HTTPS and HTTP." unless raw[:success]

      status = "#{(raw[:fetched_over] || 'http').upcase} #{raw[:status_code]}"
      status += " in #{raw[:response_time_ms]}ms" if raw[:response_time_ms]
      parts = [status]
      parts << "WordPress#{raw[:wp_version] ? " #{raw[:wp_version]}" : ''} detected" if raw[:is_wordpress]
      parts << "critical error" if raw[:critical_error]
      parts << "maintenance mode" if raw[:maintenance_mode]
      parts << (raw[:redirects_to_https] ? "HTTP→HTTPS redirect ok" : "no HTTP→HTTPS redirect")
      missing = raw[:missing_headers]&.size || 0
      parts << "#{missing} missing security header#{'s' if missing != 1}" if missing.positive?
      "#{parts.join(' · ')}."
    end
  end
end
