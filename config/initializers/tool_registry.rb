require "tool_harness/result"
require "tool_harness/registry"
require "tool_harness/tool"

# to_prepare runs once at boot in production and before every request in
# development. Rebuilding the registry each time keeps newly-added tool files
# discoverable without a server restart.
Rails.application.config.to_prepare do
  ToolHarness::Registry.reset!
  ToolHarness::Registry.auto_discover!
  Rails.logger.info "ToolHarness: Registered #{ToolHarness::Registry.tools.size} tools"
end
