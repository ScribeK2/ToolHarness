module Tools
  class WebsiteHealth
    include ToolHarness::Tool

    def self.tool_name = "Website Health (WordPress-aware)"
    def self.category = :hosting
    def self.description = "Fetches the homepage, classifies HTTP health, detects WordPress (generator/wp-paths/wp-json), and flags the WP critical-error and maintenance states."
    def self.form_fields = { domain: :text }
    def self.input_type = :domain
    def self.cacheable? = false
    def self.timeout = 20

    def execute(params)
      raw = ::WebsiteHealthChecker.check(params[:domain])

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

      parts = ["#{(raw[:fetched_over] || 'http').upcase} #{raw[:status_code]}"]
      parts << "WordPress#{raw[:wp_version] ? " #{raw[:wp_version]}" : ''} detected" if raw[:is_wordpress]
      parts << "critical error" if raw[:critical_error]
      parts << "maintenance mode" if raw[:maintenance_mode]
      "#{parts.join(' · ')}."
    end
  end
end
