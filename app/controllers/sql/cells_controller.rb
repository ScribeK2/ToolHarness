class Sql::CellsController < ApplicationController
  def show
    run = ToolRun.find(params[:id])
    row_idx = params[:row].to_i
    col_idx = params[:col].to_i
    row = (run.result_data["sample"] || [])[row_idx] or return head(:not_found)
    value = row[col_idx]
    render turbo_stream: turbo_stream.replace("sql_cell_detail",
             partial: "workbench/sql/cell_detail",
             locals:  { column: run.result_data.dig("columns", col_idx), value: value })
  end
end
