module Tools
  class WhoisLookup
    include ToolHarness::Tool

    def self.tool_name = "WHOIS Lookup"
    def self.category = :domain
    def self.description = "Retrieves registrar, expiration, nameservers, and registrant details from WHOIS, falling back to the system whois command if needed."
    def self.form_fields = { domain: :text }
    def self.input_type = :domain
    def self.cacheable? = false
    def self.timeout = 30

    def execute(params)
      raw = ::WhoisChecker.check(params[:domain])

      ToolHarness::Result.new(
        success: raw[:success],
        tool: self.class.tool_name,
        data: raw.except(:issues, :success, :raw_data).merge(raw_data: raw[:raw_data]),
        issues: raw[:issues] || [],
        summary: build_summary(raw),
        error: raw[:error]
      )
    end

    private

    def build_summary(raw)
      return "WHOIS lookup failed: #{raw[:error] || 'unknown error'}." unless raw[:success]

      parts = []
      parts << "Registered via #{raw[:registrar]}" if raw[:registrar].present?
      if raw[:expiration_date].present?
        days = days_until(raw[:expiration_date])
        if days
          parts << "expires #{raw[:expiration_date][0, 10]} (#{days} days)"
        else
          parts << "expires #{raw[:expiration_date]}"
        end
      end
      parts << "#{raw[:nameservers].size} nameservers" if raw[:nameservers]&.any?

      parts.any? ? "#{parts.join(', ')}." : "WHOIS data retrieved."
    end

    def days_until(date_str)
      (Date.parse(date_str) - Date.today).to_i
    rescue ArgumentError, TypeError
      nil
    end
  end
end
