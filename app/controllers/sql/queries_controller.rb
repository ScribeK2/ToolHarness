class Sql::QueriesController < ApplicationController
  def create
    raw = session[:sql_workbench]
    return head(:bad_request) unless raw

    # Normalize to symbol keys — session round-trips through JSON as string keys.
    state = raw.transform_keys(&:to_sym)

    sql = params[:sql].to_s
    return head(:bad_request) if sql.strip.empty?

    classification = ToolHarness::Sql::Classifier.classify(sql)
    confirmed = params[:confirmed].to_s == "true"

    # Confirm-required interception: do not persist a ToolRun until the user confirms.
    if needs_confirm?(state, classification, confirmed)
      return render turbo_stream: turbo_stream.replace("sql_confirm_overlay",
               partial: "workbench/sql/confirm_overlay",
               locals:  { sql: sql, classification: classification, database: state[:database] })
    end

    store  = ToolHarness::Sql::ConnectionStore.new
    client = store.client_for(state[:connection])
    runner = ToolHarness::Sql::Runner.new(
      client:        client,
      profile_name:  state[:connection],
      database:      state[:database],
      write_mode:    state[:write_mode],
      session_limit: state[:session_limit] || 500,
      timeout:       state[:session_timeout] || 30,
      confirmed:     confirmed
    )
    runner.define_singleton_method(:reconnect!) { store.reconnect(state[:connection]) }

    result = runner.execute(sql)
    inject = ToolHarness::Sql::LimitInjector.append(sql, state[:session_limit] || 500)

    tool_run = ToolRun.record(
      tool_class: Tools::SqlWorkbench,
      params: {
        sql:           inject[:sql],
        connection:    state[:connection],
        database:      state[:database],
        applied_limit: result.applied_limit,
        timeout:       state[:session_timeout] || 30,
        write_mode:    state[:write_mode]
      },
      result: tool_harness_result(result)
    )

    render turbo_stream: turbo_stream.replace("sql_result_panel",
             partial: "workbench/sql/result_panel",
             locals:  { result: result, run: tool_run, state: state })
  end

  private

  def needs_confirm?(state, classification, confirmed)
    state[:write_mode].to_s == "rw" &&
      !confirmed &&
      %i[write_dangerous unknown].include?(classification)
  end

  def tool_harness_result(r)
    ToolHarness::Result.new(
      success: r.success?,
      tool:    "SQL Workbench",
      data:    {
        columns:        r.columns,
        row_count:      r.row_count,
        time_ms:        r.time_ms,
        applied_limit:  r.applied_limit,
        write_affected: r.write_affected,
        sample:         sample_rows(r)
      },
      summary: build_summary(r),
      error:   r.error_message,
      execution_time: (r.time_ms / 1000.0)
    )
  end

  def sample_rows(r)
    r.rows.first(5).map { |row| row.map { |cell| cell.to_s[0, 200] } }
  end

  def build_summary(r)
    return "error: #{r.error_message}"                    unless r.success?
    return "#{r.write_affected} rows affected"            if r.write_affected
    "#{r.row_count} row#{'s' unless r.row_count == 1} in #{r.time_ms} ms"
  end
end
