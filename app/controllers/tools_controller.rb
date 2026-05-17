class ToolsController < ApplicationController
  before_action :load_tool, only: [:show]

  def index
    @tools_by_category = ToolHarness::Registry
      .tools
      .values
      .sort_by { |klass| klass.tool_name }
      .group_by(&:category)
      .sort_by { |cat, _| cat.to_s }
      .to_h
  end

  def show
    # @tool_class set by load_tool; view renders form from @tool_class.form_fields
  end

  private

  def load_tool
    @tool_class = ToolHarness::Registry.find_tool(params[:tool_key])
    raise ActionController::RoutingError, "Tool not found: #{params[:tool_key]}" unless @tool_class
  end
end
