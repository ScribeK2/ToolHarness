module Tools
  class WhoisLookup
    include ToolHarness::Tool

    def self.tool_name = "Registration Lookup (RDAP / WHOIS)"
    def self.category = :domain
    def self.description = "RDAP-first registration lookup for domains and IPs, falling back to WHOIS — registrar, key dates, nameservers, network ownership, and abuse contacts."
    def self.form_fields = { domain: :text }
    def self.input_type = :domain
    def self.cacheable? = false
    def self.timeout = 30
    def self.result_partial = "results/tools/whois_lookup"

    def execute(params)
      query = params[:domain].to_s.strip
      data  = lookup(query)

      ToolHarness::Result.new(
        success: data[:success],
        tool: self.class.tool_name,
        data: data,
        issues: data[:issues] || [],
        summary: build_summary(data),
        error: data[:error]
      )
    end

    private

    # RDAP-first ladder. IPs and domains both get a WHOIS fallback (the whois
    # gem queries RIR WHOIS for IPs). First success wins; if both miss we keep
    # the RDAP result so its error/issues surface.
    def lookup(query)
      rdap = ::RdapChecker.check(query)
      return rdap if rdap[:success]

      whois = ::WhoisChecker.check(query)
      whois[:success] ? whois : rdap.merge(error: rdap[:error] || whois[:error])
    end

    def build_summary(data)
      return "Registration lookup failed: #{data[:error] || 'unknown error'}." unless data[:success]

      via = case data[:source]
      when :rdap_registry then "via RDAP (registry)"
      when :rdap_bootstrap_redirect then "via RDAP (rdap.org)"
      when :whois_fallback then "via WHOIS fallback"
      else ""
      end

      body = data[:record_type] == :ip ? ip_summary(data) : domain_summary(data)
      "#{body} #{via}".strip
    end

    def domain_summary(data)
      parts = []
      parts << "Registered via #{data[:registrar]}" if data[:registrar].present?
      if data[:expiration_date].present?
        days = days_until(data[:expiration_date])
        parts << (days ? "expires #{data[:expiration_date][0, 10]} (#{days} days)" : "expires #{data[:expiration_date]}")
      end
      parts << "#{data[:nameservers].size} nameservers" if data[:nameservers]&.any?
      parts.any? ? parts.join(", ") : "Registration data retrieved"
    end

    def ip_summary(data)
      parts = [ data[:network_name], data[:cidr] || data[:ip_range], data[:organization] ].compact
      parts.any? ? parts.join(" · ") : "Network data retrieved"
    end

    def days_until(date_str)
      (Date.parse(date_str) - Date.today).to_i
    rescue ArgumentError, TypeError
      nil
    end
  end
end
