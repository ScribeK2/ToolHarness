module Investigations
  class Orchestrator
    def self.start(domain:, track_key: "orientation", ticket_ref: nil)
      track = Track.find(track_key)

      investigation = Investigation.create!(
        domain: domain,
        track: track.key,
        ticket_ref: ticket_ref,
        status: "running",
        started_at: Time.current
      )

      track.probes.each_with_index do |tool_key, index|
        tool_class = ToolHarness::Registry.find_tool(tool_key)
        raise ArgumentError, "Unknown probe tool: #{tool_key}" unless tool_class

        run = ToolRun.create_pending!(
          tool_class: tool_class,
          params: { domain: domain },
          investigation: investigation,
          step_order: index
        )
        ToolRunJob.perform_later(run.id)
      end

      investigation
    end
  end
end
