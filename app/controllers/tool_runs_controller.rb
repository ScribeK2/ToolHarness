class ToolRunsController < ApplicationController
  NORMALIZED_INPUT_TYPES = %i[domain host].freeze

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

  # Poll target for the spinner's run-poller fallback. 204 while the run is
  # still in flight (leave the spinner and its stream subscription alone);
  # a replace stream once terminal, mirroring the job's completion broadcast.
  def show
    tool_run = ToolRun.find(params[:id])
    return head :no_content unless ToolRun::TERMINAL_STATUSES.include?(tool_run.status)

    render turbo_stream: turbo_stream.replace(
      ActionView::RecordIdentifier.dom_id(tool_run),
      partial: "results/result",
      locals: { tool_run: tool_run }
    )
  end

  def rerun
    source     = ToolRun.find(params[:id])
    tool_class = source.tool_class
    raise ActionController::RoutingError, "Tool not found: #{source.tool_key}" unless tool_class

    @tool_run = ToolRun.create_pending!(tool_class: tool_class, params: source.input)
    ToolRunJob.perform_later(@tool_run.id)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "result_panel",
          partial: "workbench/result_panel_with_run",
          locals: { tool_run: @tool_run }
        )
      end
      format.html { redirect_to workbench_path(tool: source.tool_key, target: @tool_run.input_summary, run: @tool_run.id) }
    end
  end

  private

  def run_params(tool_class)
    permitted = tool_class.form_fields.keys
    attrs = params.fetch(:tool_run, {}).permit(*permitted).to_h.symbolize_keys
    normalize_primary_field!(attrs, tool_class)
    attrs
  end

  def normalize_primary_field!(attrs, tool_class)
    return unless NORMALIZED_INPUT_TYPES.include?(tool_class.input_type)

    primary = tool_class.form_fields.keys.first
    return unless attrs.key?(primary)

    attrs[primary] = ToolHarness::HostNormalizer.call(
      attrs[primary],
      preserve_path: tool_class.preserve_path_in_input?
    )
  end
end
