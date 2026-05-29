class InvestigationsController < ApplicationController
  layout "workbench"

  DEFAULT_SLOTS = %w[whois_lookup dns_lookup ssl_inspect email_auth_check http_inspect].freeze

  before_action :set_workbench_defaults

  def create
    investigation = Investigations::Orchestrator.start(
      domain: normalized_domain,
      track_key: params[:track].presence || "orientation",
      ticket_ref: params[:ticket_ref].presence
    )

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "result_panel",
          partial: "investigations/surface",
          locals: { investigation: investigation, selected: investigation.tool_runs.first }
        )
      end
      format.html { redirect_to investigation_path(investigation) }
    end
  rescue KeyError
    head :unprocessable_entity
  end

  def show
    @investigation = Investigation.find(params[:id])
    @selected = @investigation.tool_runs.find_by(id: params[:step]) || @investigation.tool_runs.first
    @view = "investigation"   # keep the rail out of "history" mode; the layout branches on @investigation.present?
  end

  private

  def normalized_domain
    ToolHarness::HostNormalizer.call(params[:domain].to_s)
  end

  def set_workbench_defaults
    @default_slots = DEFAULT_SLOTS
    @target        = params[:target].to_s
    @tool_key      = nil
  end
end
