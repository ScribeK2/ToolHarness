module Tools
  class DnsLookup
    include ToolHarness::Tool

    DEPTHS       = %w[quick worldwide].freeze
    RECORD_TYPES = %w[A AAAA MX NS CNAME TXT SOA CAA].freeze

    def self.tool_name = "DNS Lookup"
    def self.category = :dns
    def self.description = "Resolves A, AAAA, MX, NS, CNAME, and TXT records (quick: Google + Cloudflare), or checks one record type across 20 resolvers worldwide (worldwide depth) and flags propagation mismatches."
    def self.form_fields = {
      domain: :text,
      depth: { type: :select, options: DEPTHS },
      record_type: { type: :select, options: RECORD_TYPES }
    }
    def self.input_type = :domain
    def self.cacheable? = false
    def self.result_partial = "results/tools/dns_lookup"

    def execute(params)
      depth = params[:depth].presence || "quick"
      depth == "worldwide" ? execute_worldwide(params) : execute_quick(params)
    end

    private

    def execute_quick(params)
      raw = ::DnsChecker.check(params[:domain])

      ToolHarness::Result.new(
        success: raw[:success],
        tool: self.class.tool_name,
        data: raw.except(:issues, :success),
        issues: raw[:issues] || [],
        summary: quick_summary(raw)
      )
    end

    def execute_worldwide(params)
      raw = ::PropagationChecker.check(
        params[:domain],
        record_type: params[:record_type].presence || "A"
      )

      ToolHarness::Result.new(
        success: raw[:success],
        tool: self.class.tool_name,
        data: raw.except(:issues, :success),
        issues: raw[:issues] || [],
        summary: propagation_summary(raw)
      )
    end

    def quick_summary(raw)
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

    def propagation_summary(raw)
      total = raw[:resolvers].size
      rtype = raw[:record_type]

      # NXDOMAIN sweep
      if raw[:issues].any? { |i| i[:code] == "nxdomain_consensus" }
        return "Domain #{raw[:domain]} does not exist (NXDOMAIN across all #{total} resolvers)."
      end

      # All failed (no OK responses)
      if raw[:consensus].nil? && raw[:dissenters].empty? && raw[:failures].size == total
        return "No resolver responded — #{total} of #{total} failed."
      end

      # No consensus
      if raw[:consensus].nil?
        distinct = raw[:dissenters].map { |r| r[:values].sort }.uniq.size
        responding = raw[:dissenters].size
        return "No DNS propagation consensus — #{distinct} distinct values across #{responding} resolvers."
      end

      # Consensus reached
      count = raw[:consensus][:count]
      ok_total = raw[:consensus][:total]
      extras = []
      extras << "#{raw[:dissenters].size} dissent#{'s' if raw[:dissenters].size != 1}"  if raw[:dissenters].any?
      extras << "#{raw[:failures].size} failure#{'s' if raw[:failures].size != 1}"      if raw[:failures].any?
      suffix = extras.any? ? " (#{extras.join(', ')})" : ""

      "#{rtype} record fully propagated to #{count}/#{ok_total} resolvers#{suffix}."
    end
  end
end
