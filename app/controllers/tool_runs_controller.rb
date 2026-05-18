class ToolRunsController < ApplicationController
  def create
    tool_class = ToolHarness::Registry.find_tool(params[:tool_key])
    raise ActionController::RoutingError, "Tool not found: #{params[:tool_key]}" unless tool_class

    @tool_run = ToolRun.create_pending!(
      tool_class: tool_class,
      params: run_params(tool_class)
    )

    ToolRunJob.perform_later(@tool_run.id)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "result_panel",
          partial: "workbench/result_panel_with_run",
          locals: { tool_run: @tool_run }
        )
      end
      format.html { redirect_to workbench_path(tool: params[:tool_key], target: @tool_run.input_summary, run: @tool_run.id) }
    end
  end

  private

  def run_params(tool_class)
    permitted = tool_class.form_fields.keys
    params.fetch(:tool_run, {}).permit(*permitted).to_h.symbolize_keys
  end
end
