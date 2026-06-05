class WorkbenchController < ApplicationController
  include WorkbenchDefaults

  layout "workbench"

  def show
    @view          = params[:view].to_s
    @tool_key      = params[:tool].presence || ToolHarness::Registry.tools.keys.first&.to_s
    @tool_class    = ToolHarness::Registry.find_tool(@tool_key) if @tool_key
    @target        = params[:target].to_s
    @run           = ToolRun.find_by(id: params[:run]) if params[:run].present?
    @default_slots  = DEFAULT_SLOTS
    @custom_partial = (@tool_class.respond_to?(:custom_partial) ? @tool_class.custom_partial : nil)

    if @view == "history"
      @filter = params[:filter].to_s
      scope   = ToolRun.recent.where(investigation_id: nil)
      @runs   = ToolHarness::RunFilter.apply(scope, @filter).limit(200)
      @errors = ToolHarness::RunFilter.errors_for(@filter)
    end
  end
end
