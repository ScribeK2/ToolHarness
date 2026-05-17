require "test_helper"

# The legacy GET /tools and GET /tools/:tool_key routes were removed in Task 8.1;
# the workbench replaces the catalog and per-tool form. The only remaining
# tool-related HTTP endpoint is POST /tools/:tool_key/run, which is covered by
# ToolRunsControllerTest.
class ToolsControllerTest < ActionDispatch::IntegrationTest
end
