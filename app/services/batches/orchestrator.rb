module Batches
  class Orchestrator
    MAX_DOMAINS  = 50
    DOMAIN_REGEX = /\A[a-zA-Z0-9](?:[a-zA-Z0-9\-]*[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9\-]*[a-zA-Z0-9])?)+\z/

    def self.start(tool_key:, domains:)
      tool_class = ToolHarness::Registry.find_tool(tool_key)
      raise ArgumentError, "Unknown tool: #{tool_key}" unless tool_class
      raise ArgumentError, "Tool #{tool_key} does not accept a domain input" unless tool_class.form_fields.key?(:domain)

      list = parse_domains(domains)
      raise ArgumentError, "No valid domains provided" if list.empty?

      batch = Batch.create!(tool_key: tool_class.name.demodulize.underscore, status: "running", domain_count: list.size)
      list.each_with_index do |domain, index|
        run = ToolRun.create_pending!(tool_class: tool_class, params: { domain: domain }, batch: batch, step_order: index)
        ToolRunJob.perform_later(run.id)
      end
      batch
    end

    def self.parse_domains(raw)
      raw.to_s.split(/[\s,;]+/).map(&:strip).reject(&:empty?).uniq
        .select { |d| d.size <= 253 && d.match?(DOMAIN_REGEX) }.first(MAX_DOMAINS)
    end
  end
end
