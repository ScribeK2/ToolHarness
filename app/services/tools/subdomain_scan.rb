module Tools
  class SubdomainScan
    include ToolHarness::Tool

    def self.tool_name = "Subdomain Scan"
    def self.category = :dns
    def self.description = "Probes a domain for common subdomains (www, mail, api, admin, cpanel, etc.) and groups discoveries by purpose."
    def self.form_fields = { domain: :text }
    def self.input_type = :domain
    def self.cacheable? = false
    def self.timeout = 60

    def execute(params)
      raw = ::SubdomainScanner.scan(params[:domain])

      ToolHarness::Result.new(
        success: raw[:success],
        tool: self.class.tool_name,
        data: raw.except(:success),
        issues: [],
        summary: build_summary(raw)
      )
    end

    private

    def build_summary(raw)
      found_count = raw[:found]&.size || 0
      total = found_count + (raw[:not_found]&.size || 0)

      return "Subdomain scan ran but found no live subdomains (#{total} checked)." if found_count.zero?

      by_type = raw[:found].group_by { |s| s[:type] }.transform_values(&:size)
      breakdown = by_type.sort_by { |_, v| -v }.first(3).map { |type, count| "#{count} #{type}" }.join(", ")
      "Found #{found_count} of #{total} probed subdomains (#{breakdown})."
    end
  end
end
