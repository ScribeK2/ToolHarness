# app/services/tools/dns_propagation.rb
module Tools
  class DnsPropagation
    include ToolHarness::Tool

    def self.tool_name   = "DNS Propagation"
    def self.category    = :dns
    def self.description = "Checks how DNS resolvers worldwide see a record — like dnschecker.org but local."
    def self.input_type  = :domain
    def self.cacheable?  = false
    def self.timeout     = 15
    def self.result_partial = "results/tools/dns_propagation"
    def self.form_fields = {
      domain: :text,
      record_type: { type: :select, options: %w[A AAAA MX NS CNAME TXT SOA CAA] }
    }

    def execute(params)
      raw = ::PropagationChecker.check(
        params[:domain],
        record_type: params[:record_type].presence || "A"
      )

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
