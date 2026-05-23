module Tools
  class SqlWorkbench
    include ToolHarness::Tool

    def self.tool_name      = "SQL Workbench"
    def self.category       = :database
    def self.description    = "Connect to a MySQL-protocol database (incl. TiDB), run ad-hoc queries against client data, and read results in a keyboard-driven tabular grid. Read-only by default."
    def self.input_type     = :sql
    def self.cacheable?     = false
    def self.timeout        = 30
    def self.form_fields    = { sql: :text }
    def self.custom_partial = "workbench/sql/pane"

    # NB: This tool does not implement #execute. SQL execution happens inline
    # via Sql::QueriesController, which has direct access to session state
    # (active connection, write mode, etc.) that a background job does not.
    # The tool class exists for: registry presence, category placement,
    # ToolRun.tool_name / category persistence, and custom_partial routing.
    def execute(_params)
      raise NotImplementedError, "Tools::SqlWorkbench runs inline via Sql::QueriesController"
    end
  end
end
