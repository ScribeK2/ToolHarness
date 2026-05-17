class WorkbenchController < ApplicationController
  layout "workbench"

  DEFAULT_SLOTS = %w[whois_lookup dns_lookup ssl_inspect email_auth_check http_inspect].freeze

  def show
    @tool_key   = params[:tool].presence || ToolHarness::Registry.tools.keys.first&.to_s
    @tool_class = ToolHarness::Registry.find_tool(@tool_key) if @tool_key
    @target     = params[:target].to_s
    @run        = current_user.tool_runs.find_by(id: params[:run]) if params[:run].present?
    @default_slots = DEFAULT_SLOTS
  end
end
