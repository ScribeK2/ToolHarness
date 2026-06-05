module Tools
  class Credentials
    include ToolHarness::Tool

    def self.tool_name      = "Credentials"
    def self.category       = :config
    def self.description    = "Stores API keys and per-host credentials (encrypted at rest) for tools that need them."
    def self.input_type     = :config
    def self.cacheable?     = false
    def self.form_fields    = { secret: :password }
    def self.custom_partial = "credentials/pane"

    # Managed inline via Credentials::EntriesController (needs no background job).
    # The class exists for registry presence, :config rail placement, and
    # custom_partial routing — mirroring Tools::SqlWorkbench.
    def execute(_params)
      raise NotImplementedError, "Tools::Credentials is managed via Credentials::EntriesController"
    end
  end
end
