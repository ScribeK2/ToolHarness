class ToolRunJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: 5.seconds, attempts: 2

  def perform(tool_run_id)
    tool_run = ToolRun.find(tool_run_id)
    tool_class = ToolHarness::Registry.find_tool(tool_run.tool_key)

    unless tool_class
      tool_run.update!(
        status: "failed",
        success: false,
        error: "Unknown tool: #{tool_run.tool_key}",
        completed_at: Time.current
      )
      broadcast(tool_run)
      return
    end

    started_at = Time.current
    tool_run.update!(status: "processing", started_at: started_at)
    broadcast(tool_run)

    params = (tool_run.input || {}).symbolize_keys
    result = tool_class.new.run(params)
    tool_run.apply_result!(result, started_at: started_at, completed_at: Time.current)

    broadcast(tool_run)
  end

  private

  def broadcast(tool_run)
    Turbo::StreamsChannel.broadcast_replace_to(
      tool_run,
      target: ActionView::RecordIdentifier.dom_id(tool_run),
      partial: "tool_runs/result",
      locals: { tool_run: tool_run }
    )
  rescue StandardError => e
    # Broadcast failures shouldn't kill the job (the result is already
    # persisted), but log loudly — silently dropped broadcasts hide bugs
    # like missing partials and stream-name mismatches.
    Rails.logger.error "ToolRunJob broadcast failed for run ##{tool_run.id}: #{e.class}: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n") if e.backtrace
  end
end
