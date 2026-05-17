module Tools
  class DmarcCheck
    include ToolHarness::Tool

    def self.tool_name = "DMARC Check"
    def self.category = :email_auth
    def self.description = "Reads the _dmarc TXT record, parses policy, subdomain policy, enforcement percentage, alignment modes, and aggregate/forensic report destinations."
    def self.form_fields = { domain: :text }
    def self.input_type = :domain
    def self.cacheable? = false

    def execute(params)
      raw = ::DmarcChecker.check(params[:domain])

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
      return "DMARC: #{raw[:error] || 'no record found'}." unless raw[:success]

      policy = raw[:policy].presence || "no policy"
      pct = raw[:percentage] || 100
      enforcement = pct == 100 ? "" : " (#{pct}% enforcement)"

      rua = raw[:rua]&.size || 0
      reports = if rua.zero?
        ", no aggregate reports"
      else
        ", #{rua} aggregate report address#{rua == 1 ? '' : 'es'}"
      end

      "DMARC: p=#{policy}#{enforcement}#{reports}."
    end
  end
end
