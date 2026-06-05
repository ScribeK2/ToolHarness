class BatchesController < ApplicationController
  include WorkbenchDefaults
  layout "workbench"
  before_action :set_workbench_defaults

  def create
    batch = Batches::Orchestrator.start(tool_key: params[:tool_key], domains: params[:domains])
    redirect_to batch_path(batch)
  rescue ArgumentError => e
    redirect_to workbench_path(tool: "bulk_run"), alert: e.message
  end

  def show
    @batch = Batch.find(params[:id])
    @view  = "batch"
  end

  private

  def set_workbench_defaults
    @default_slots = DEFAULT_SLOTS
    @target        = ""
    @tool_key      = nil
  end
end
