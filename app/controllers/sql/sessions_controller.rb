class Sql::SessionsController < ApplicationController
  def create
    store = ToolHarness::Sql::ConnectionStore.new
    profile = store.find(params[:profile_name].to_s)
    return render_picker_error("no such profile") unless profile

    begin
      store.client_for(profile[:name])  # validates connectivity + credentials
    rescue StandardError => e
      return render_picker_error(e.message)
    end

    session[:sql_workbench] = {
      connection:      profile[:name],
      database:        profile[:default_database],
      write_mode:      profile[:default_mode],
      session_limit:   500,
      session_timeout: 30
    }
    render turbo_stream: turbo_stream.replace("sql_pane",
             partial: "workbench/sql/pane",
             locals:  pane_locals)
  end

  def destroy
    wb = session[:sql_workbench]
    if wb && (name = wb[:connection] || wb["connection"])
      ToolHarness::Sql::ConnectionStore.new.disconnect(name)
    end
    session.delete(:sql_workbench)
    render turbo_stream: turbo_stream.replace("sql_pane",
             partial: "workbench/sql/pane", locals: pane_locals)
  end

  def update
    raw = session[:sql_workbench] || {}
    # Normalize to symbol keys (session round-trips through JSON as string keys).
    s = raw.transform_keys(&:to_sym)

    if params[:database].present?
      s[:database] = params[:database].to_s
      run_use_database(s)
    end
    s[:write_mode]      = params[:write_mode].to_s        if params[:write_mode].present?
    s[:session_limit]   = params[:session_limit].to_i     if params[:session_limit].present?
    s[:session_timeout] = params[:session_timeout].to_i   if params[:session_timeout].present?

    session[:sql_workbench] = s
    render turbo_stream: turbo_stream.replace("sql_pane",
             partial: "workbench/sql/pane", locals: pane_locals)
  end

  private

  def run_use_database(s)
    store  = ToolHarness::Sql::ConnectionStore.new
    client = store.client_for(s[:connection])
    bt     = "\x60"
    quoted = "#{bt}#{s[:database].to_s.gsub(bt, bt * 2)}#{bt}"
    client.query("USE #{quoted}")
  rescue StandardError
    # Surfaced in pane via the next query attempt.
  end

  def pane_locals
    { state: session[:sql_workbench], profiles: ToolHarness::Sql::ConnectionStore.new.profiles, run: nil, error: nil }
  end

  def render_picker_error(message)
    render turbo_stream: turbo_stream.replace("sql_connection_picker",
             partial: "workbench/sql/connection_picker",
             locals:  { profiles: ToolHarness::Sql::ConnectionStore.new.profiles, state: "list", error: message })
  end
end
