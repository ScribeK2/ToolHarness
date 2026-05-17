module Tools
  class SpfCheck
    include ToolHarness::Tool

    def self.tool_name = "SPF Check"
    def self.category = :email_auth
    def self.description = "Looks up the SPF TXT record, parses mechanisms and qualifiers, and flags permissive policies, deprecated mechanisms, and DNS lookup overflow."
    def self.form_fields = { domain: :text }
    def self.input_type = :domain
    def self.cacheable? = false

    def execute(params)
      raw = ::SpfChecker.check(params[:domain])

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
      return "SPF: #{raw[:error] || 'no record found'}." unless raw[:success]

      all = raw[:all_mechanism]
      policy = all ? "#{all[:qualifier]}all" : "no 'all' mechanism"
      includes = raw[:includes]&.size || 0
      lookups = raw[:dns_lookup_count] || 0
      "SPF record found (#{policy}, #{lookups} DNS lookups, #{includes} includes)."
    end
  end
end
