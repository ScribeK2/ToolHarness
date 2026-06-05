module Tools
  class BulkRun
    include ToolHarness::Tool

    MAX_DOMAINS = 50

    def self.tool_name      = "Bulk Domain Runner"
    def self.category       = :diagnostics
    def self.description    = "Runs a chosen domain-input tool against up to #{MAX_DOMAINS} domains in parallel — each its own inspectable run, with live progress."
    def self.input_type     = :bulk
    def self.cacheable?     = false
    def self.custom_partial = "batches/form"

    def self.form_fields
      {
        domains:  { type: :textarea, label: "Domains (one per line, comma, or whitespace separated — max #{MAX_DOMAINS})", rows: 8 },
        tool_key: { type: :select, label: "Tool to run on each domain", options: selectable_tools }
      }
    end

    def self.selectable_tools
      ToolHarness::Registry.tools
        .reject { |key, _| key == :bulk_run }
        .select { |_, klass| klass.form_fields.key?(:domain) }
        .map    { |key, klass| [klass.tool_name, key.to_s] }
        .sort_by(&:first)
    end

    # Launches a Batch via BatchesController (Solid-Queue fan-out); no inline execution.
    def execute(_params)
      raise NotImplementedError, "Tools::BulkRun launches a Batch via BatchesController"
    end
  end
end
