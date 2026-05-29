class InvestigationProgressJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(investigation_id)
    investigation = Investigation.find(investigation_id)

    correlate_if_ready(investigation)
    broadcast(investigation)
  end

  private

  def correlate_if_ready(investigation)
    investigation.with_lock do
      return unless investigation.running?

      Investigations::StepScheduler.new(investigation).call
      return unless investigation.all_steps_terminal?

      track  = investigation.track_config
      result = track.correlator.new(investigation.tool_runs.reload.to_a).call

      investigation.update!(
        verdict_status: result.verdict_status,
        findings: result.findings,
        suggested_track: result.suggested_track,
        status: "completed",
        completed_at: Time.current
      )
    end
  end

  def broadcast(investigation)
    Turbo::StreamsChannel.broadcast_replace_to(
      investigation,
      target: "investigation_steps_#{investigation.id}",
      partial: "investigations/steps",
      locals: { investigation: investigation, selected: investigation.tool_runs.first }
    )
    Turbo::StreamsChannel.broadcast_replace_to(
      investigation,
      target: "investigation_verdict_#{investigation.id}",
      partial: "investigations/verdict",
      locals: { investigation: investigation }
    )
    Turbo::StreamsChannel.broadcast_replace_to(
      investigation,
      target: "investigation_report_#{investigation.id}",
      partial: "investigations/report_button",
      locals: { investigation: investigation }
    )
  rescue StandardError => e
    Rails.logger.error "InvestigationProgressJob broadcast failed for ##{investigation.id}: #{e.class}: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n") if e.backtrace
  end
end
