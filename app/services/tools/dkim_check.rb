module Tools
  class DkimCheck
    include ToolHarness::Tool

    def self.tool_name = "DKIM Check"
    def self.category = :email_auth
    def self.description = "Queries a list of common DKIM selectors (default, google, k1, sendgrid, mailgun, etc.) under _domainkey, parses any keys found, and reports key strength and testing flags."
    def self.form_fields = { domain: :text }
    def self.input_type = :domain
    def self.cacheable? = false
    def self.timeout = 60

    def execute(params)
      raw = ::DkimChecker.check(params[:domain])

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
      found = raw[:selectors_found] || []
      checked = raw[:selectors_checked] || 0

      if found.empty?
        return "DKIM: no selectors found among #{checked} common selectors checked."
      end

      names = found.map { |s| s[:selector] }.first(3).join(", ")
      more = found.size > 3 ? ", …" : ""
      "DKIM: #{found.size} of #{checked} selectors found (#{names}#{more})."
    end
  end
end
