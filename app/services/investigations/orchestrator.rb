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

      track.specs.each_with_index do |spec, index|
        tool_class = ToolHarness::Registry.find_tool(spec.tool_key)
        raise ArgumentError, "Unknown probe tool: #{spec.tool_key}" unless tool_class

        run = ToolRun.create_pending!(
          tool_class: tool_class,
          params: { domain: domain },
          investigation: investigation,
          step_order: index
        )
        # Dependent probes are enqueued later by the StepScheduler once their
        # dependency resolves (or skipped if it can't be resolved).
        ToolRunJob.perform_later(run.id) unless spec.depends_on
      end

      investigation
    end
  end
end
