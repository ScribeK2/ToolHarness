module Tools
  class TicketLookup
    include ToolHarness::Tool

    def self.tool_name = "Ticket Lookup"
    def self.category = :diagnostics
    def self.description = "Stub for future integration with the internal ticketing API. Echoes the ticket ID and surfaces a placeholder result; the field is wired so the real API hookup is a drop-in change."
    def self.form_fields = { ticket_id: :text }
    def self.input_type = :ticket
    def self.cacheable? = false

    def execute(params)
      ticket_id = params[:ticket_id].to_s.strip

      if ticket_id.empty?
        return ToolHarness::Result.new(
          success: false,
          tool: self.class.tool_name,
          error: "ticket_id is required",
          summary: "Missing ticket ID"
        )
      end

      ToolHarness::Result.new(
        success: true,
        tool: self.class.tool_name,
        data: {
          ticket_id: ticket_id,
          status: "stub",
          integration_pending: true
        },
        issues: [{
          severity: "info",
          code: "ticket_lookup_stub",
          title: "Internal ticketing API not yet integrated",
          message: "This tool is a placeholder. Once the internal ticketing API is available, it will return ticket details, current owner, status, and history.",
          recommendation: "Replace the stub in app/services/tools/ticket_lookup.rb with the real API client."
        }],
        summary: "Ticket #{ticket_id} — lookup stub (integration pending)."
      )
    end
  end
end
