module Tools
  class EmailAuthCheck
    include ToolHarness::Tool

    SCOPES = %w[full spf dkim dmarc].freeze

    def self.tool_name = "Email Authentication"
    def self.category = :email
    def self.description = "Runs SPF, DKIM, and DMARC together with an A–F grade and cross-record issues — or a focused single-record check via the scope selector."
    def self.form_fields = {
      domain: :text,
      scope: { type: :select, options: SCOPES }
    }
    def self.input_type = :domain
    def self.cacheable? = false
    def self.timeout = 90

    def execute(params)
      scope = params[:scope].presence || "full"
      scope = "full" unless SCOPES.include?(scope)
      scope == "full" ? execute_full(params[:domain]) : execute_scoped(params[:domain], scope)
    end

    private

    def execute_full(domain)
      # Pull MX records (cached) so the "MX without SPF" cross-issue check fires correctly.
      dns_raw = ::DnsChecker.check(domain)
      mx_records = dns_raw[:success] ? dns_raw[:mx_records] : nil

      raw = ::EmailChecker.check(domain, mx_records: mx_records)

      ToolHarness::Result.new(
        success: raw[:success],
        tool: self.class.tool_name,
        data: raw.except(:issues, :success, :recommendations).merge(scope: "full"),
        issues: raw[:issues] || [],
        recommendations: raw[:recommendations] || [],
        summary: full_summary(raw),
        error: raw[:error]
      )
    end

    # A grade over a single record is meaningless, so scoped runs return just
    # the focused checker's result — same shape the standalone tools produced.
    def execute_scoped(domain, scope)
      checker = { "spf" => ::SpfChecker, "dkim" => ::DkimChecker, "dmarc" => ::DmarcChecker }.fetch(scope)
      raw = checker.check(domain)

      ToolHarness::Result.new(
        success: raw[:success],
        tool: self.class.tool_name,
        data: raw.except(:issues, :success).merge(scope: scope),
        issues: raw[:issues] || [],
        summary: send(:"#{scope}_summary", raw),
        error: raw[:error]
      )
    end

    def full_summary(raw)
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

    def spf_summary(raw)
      return "SPF: #{raw[:error] || 'no record found'}." unless raw[:success]

      all = raw[:all_mechanism]
      policy = all ? "#{all[:qualifier]}all" : "no 'all' mechanism"
      includes = raw[:includes]&.size || 0
      lookups = raw[:dns_lookup_count] || 0
      "SPF record found (#{policy}, #{lookups} DNS lookups, #{includes} includes)."
    end

    def dkim_summary(raw)
      found = raw[:selectors_found] || []
      checked = raw[:selectors_checked] || 0

      if found.empty?
        return "DKIM: no selectors found among #{checked} common selectors checked."
      end

      names = found.map { |s| s[:selector] }.first(3).join(", ")
      more = found.size > 3 ? ", …" : ""
      "DKIM: #{found.size} of #{checked} selectors found (#{names}#{more})."
    end

    def dmarc_summary(raw)
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
