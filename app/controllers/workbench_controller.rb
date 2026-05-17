class WorkbenchController < ApplicationController
  def show
    @tool_key  = params[:tool].presence || ToolHarness::Registry.tools.keys.first&.to_s
    @tool_class = ToolHarness::Registry.find_tool(@tool_key) if @tool_key
    @target    = params[:target].to_s
    @run       = current_user.tool_runs.find_by(id: params[:run]) if params[:run].present?
  end
end
