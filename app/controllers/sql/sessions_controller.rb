class Sql::SessionsController < ApplicationController
  def create
    if params[:profile_name].to_s.empty?
      create_adhoc
    else
      create_from_profile
    end
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

    db_error = nil
    if params[:database].present?
      requested = params[:database].to_s
      err = run_use_database(s.merge(database: requested))
      if err
        db_error = "#{requested}: #{err}"
        # Don't overwrite the chip — keep the real current database in session.
      else
        s[:database] = requested
      end
    end
    s[:write_mode]      = params[:write_mode].to_s        if params[:write_mode].present?
    s[:session_limit]   = params[:session_limit].to_i     if params[:session_limit].present?
    s[:session_timeout] = params[:session_timeout].to_i   if params[:session_timeout].present?

    session[:sql_workbench] = s
    streams = [turbo_stream.replace("sql_pane",
                  partial: "workbench/sql/pane", locals: pane_locals)]
    if db_error
      streams << turbo_stream.replace("sql_result_panel",
                   partial: "workbench/sql/error_block",
                   locals:  { message: ":db failed — #{db_error}", code: "USE_FAILED" })
    end
    render turbo_stream: streams
  end

  private

  def create_from_profile
    store = ToolHarness::Sql::ConnectionStore.new
    profile = store.find(params[:profile_name].to_s)
    return render_picker_error("no such profile") unless profile

    begin
      store.client_for(profile[:name])
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

  def create_adhoc
    host = params[:host].to_s
    user = params[:user].to_s
    if host.empty? || user.empty?
      return render_picker_error("ad-hoc connect requires host=, user= (and password= unless empty)")
    end

    store = ToolHarness::Sql::ConnectionStore.new
    begin
      store.client_for_adhoc(
        host:     host,
        port:     (params[:port].presence || 4000),
        user:     user,
        password: params[:password].to_s,
        database: params[:database].presence,
        tls_mode: (params[:tls_mode].presence || "prefer")
      )
    rescue StandardError => e
      return render_picker_error(e.message)
    end

    session[:sql_workbench] = {
      connection:      "_adhoc",
      database:        params[:database].to_s,
      write_mode:      "ro",
      session_limit:   500,
      session_timeout: 30
    }
    render turbo_stream: turbo_stream.replace("sql_pane",
             partial: "workbench/sql/pane",
             locals:  pane_locals)
  end

  # Returns nil on success, or an error message string on failure. Caller is
  # responsible for surfacing the error to the user; do not swallow silently.
  def run_use_database(s)
    store  = ToolHarness::Sql::ConnectionStore.new
    client = store.client_for(s[:connection])
    bt     = "\x60"
    quoted = "#{bt}#{s[:database].to_s.gsub(bt, bt * 2)}#{bt}"
    client.query("USE #{quoted}")
    nil
  rescue StandardError => e
    e.message
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
