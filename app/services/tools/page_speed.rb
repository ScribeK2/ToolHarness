module Tools
  class PageSpeed
    include ToolHarness::Tool

    def self.tool_name = "Page Speed Report"
    def self.category  = :performance
    def self.description = "GTmetrix-style page performance report — Lighthouse scores, Web Vitals, " \
      "structure recommendations and a request waterfall via Google PageSpeed Insights. " \
      "An optional Google API key (Credentials tool, id: pagespeed) raises the rate limit."
    def self.input_type             = :domain
    def self.preserve_path_in_input? = true
    def self.cacheable?             = true
    def self.cache_duration         = 10.minutes
    def self.timeout                = 60
    def self.result_partial         = "results/tools/page_speed"
    def self.form_fields = {
      domain:   :text,
      strategy: { type: :select, options: %w[mobile desktop] }
    }

    def execute(params)
      url = normalize_url(params[:domain])
      if url.blank?
        return ToolHarness::Result.new(
          success: false, tool: self.class.tool_name,
          error: "Enter a URL to test.", summary: "No URL provided."
        )
      end

      strategy = params[:strategy].presence_in(%w[mobile desktop]) || "mobile"
      key      = ToolHarness::CredentialStore.new.secret_for("pagespeed")

      raw = ::PagespeedChecker.check(url, strategy: strategy, key: key)
      unless raw[:success]
        return ToolHarness::Result.new(
          success: false, tool: self.class.tool_name,
          error: raw[:error], summary: "PageSpeed test failed: #{raw[:error]}"
        )
      end

      parsed = ::PagespeedParser.parse(raw[:body], strategy: strategy)
      ToolHarness::Result.new(
        success: true, tool: self.class.tool_name,
        data: parsed[:data], issues: parsed[:issues], summary: parsed[:summary]
      )
    end

    private

    def normalize_url(input)
      s = input.to_s.strip
      return "" if s.empty?
      s = "https://#{s}" unless s.match?(%r{\Ahttps?://}i)
      s
    end
  end
end
