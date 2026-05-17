class WorkbenchController < ApplicationController
  layout "workbench"

  DEFAULT_SLOTS = %w[whois_lookup dns_lookup ssl_inspect email_auth_check http_inspect].freeze

  def show
    @view          = params[:view].to_s
    @tool_key      = params[:tool].presence || ToolHarness::Registry.tools.keys.first&.to_s
    @tool_class    = ToolHarness::Registry.find_tool(@tool_key) if @tool_key
    @target        = params[:target].to_s
    @run           = current_user.tool_runs.find_by(id: params[:run]) if params[:run].present?
    @default_slots = DEFAULT_SLOTS

    if @view == "history"
      @filter = params[:filter].to_s
      scope   = current_user.tool_runs.recent
      @runs   = ToolHarness::RunFilter.apply(scope, @filter).limit(200)
      @errors = ToolHarness::RunFilter.errors_for(@filter)
    end
  end
end
