class WorkbenchController < ApplicationController
  include WorkbenchDefaults

  layout "workbench"

  # Old bookmarks/deep links to tools retired in the v1.0.0 consolidation.
  # nil → no absorbing tool; land on the workbench root.
  RETIRED_TOOL_REDIRECTS = {
    "spf_check"       => "email_auth_check",
    "dkim_check"      => "email_auth_check",
    "dmarc_check"     => "email_auth_check",
    "dns_propagation" => "dns_lookup",
    "ping"            => "hosting_diagnostic",
    "website_health"  => "website_inspect",
    "http_inspect"    => "website_inspect",
    "ticket_lookup"   => nil,
    "traceroute"      => nil
  }.freeze

  def show
    if RETIRED_TOOL_REDIRECTS.key?(params[:tool])
      replacement = RETIRED_TOOL_REDIRECTS[params[:tool]]
      return redirect_to workbench_path(
        { tool: replacement, target: params[:target].presence }.compact
      )
    end

    @view          = params[:view].to_s
    @tool_key      = params[:tool].presence || ToolHarness::Registry.tools.keys.first&.to_s
    @tool_class    = ToolHarness::Registry.find_tool(@tool_key) if @tool_key
    @target        = params[:target].to_s
    @run           = ToolRun.find_by(id: params[:run]) if params[:run].present?
    @default_slots  = DEFAULT_SLOTS
    @custom_partial = (@tool_class.respond_to?(:custom_partial) ? @tool_class.custom_partial : nil)

    if @view == "history"
      @filter = params[:filter].to_s
      scope   = ToolRun.recent.where(investigation_id: nil, batch_id: nil)
      @runs   = ToolHarness::RunFilter.apply(scope, @filter).limit(200)
      @errors = ToolHarness::RunFilter.errors_for(@filter)
    end
  end
end
