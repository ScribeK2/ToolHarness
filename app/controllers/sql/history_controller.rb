class Sql::HistoryController < ApplicationController
  def index
    @runs = ToolRun.for_tool(:sql_workbench).recent.limit(20)
    render turbo_stream: turbo_stream.replace("sql_history_overlay",
             partial: "workbench/sql/history_overlay",
             locals:  { runs: @runs })
  end
end
