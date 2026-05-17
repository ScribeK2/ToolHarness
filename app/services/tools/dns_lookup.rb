module Tools
  class DnsLookup
    include ToolHarness::Tool

    def self.tool_name = "DNS Lookup"
    def self.category = :dns
    def self.description = "Resolves A, AAAA, MX, NS, CNAME, and TXT records via multiple public resolvers and flags propagation mismatches."
    def self.form_fields = { domain: :text }
    def self.input_type = :domain
    def self.cacheable? = false

    def execute(params)
      raw = ::DnsChecker.check(params[:domain])

      ToolHarness::Result.new(
        success: raw[:success],
        tool: self.class.tool_name,
        data: raw.except(:issues, :success),
        issues: raw[:issues] || [],
        summary: build_summary(raw)
      )
    end

    private

    def build_summary(raw)
      return "DNS resolution failed: #{raw[:errors]&.first || 'no resolvers responded'}." unless raw[:success]

      counts = []
      counts << "#{raw[:a_records].size} A"        if raw[:a_records].any?
      counts << "#{raw[:aaaa_records].size} AAAA"  if raw[:aaaa_records].any?
      counts << "#{raw[:mx_records].size} MX"      if raw[:mx_records].any?
      counts << "#{raw[:ns_records].size} NS"      if raw[:ns_records].any?
      counts << "#{raw[:cname_records].size} CNAME" if raw[:cname_records].any?

      primary_ip = raw[:a_records].first
      base = primary_ip ? "Resolves to #{primary_ip}" : "Domain resolves"
      base += " (#{counts.join(', ')})" if counts.any?
      base += "."
    end
  end
end
