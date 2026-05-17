class ToolRunsController < ApplicationController
  before_action :load_run, only: [:show]

  def index
    scope = current_user.tool_runs.recent
    scope = scope.for_category(params[:category]) if params[:category].present?
    scope = scope.for_tool(params[:tool])         if params[:tool].present?
    scope = scope.successful                       if params[:filter] == "successful"
    scope = scope.failed_runs                      if params[:filter] == "failed"
    scope = scope.search_input(params[:q])        if params[:q].present?
    @tool_runs = scope.limit(100)

    @categories = ToolHarness::Registry.all_categories
    @tools      = ToolHarness::Registry.tools.sort_by { |key, _| key.to_s }
  end

  def show
    # @tool_run set by load_run
  end

  def create
    tool_class = ToolHarness::Registry.find_tool(params[:tool_key])
    raise ActionController::RoutingError, "Tool not found: #{params[:tool_key]}" unless tool_class

    @tool_run = ToolRun.create_pending!(
      user: current_user,
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

  def load_run
    @tool_run = current_user.tool_runs.find(params[:id])
  end

  def run_params(tool_class)
    permitted = tool_class.form_fields.keys
    params.fetch(:tool_run, {}).permit(*permitted).to_h.symbolize_keys
  end
end
