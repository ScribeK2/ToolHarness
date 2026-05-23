class Sql::ProfilesController < ApplicationController
  def new
    s = store
    render turbo_stream: turbo_stream.replace("sql_connection_picker",
             partial: "workbench/sql/connection_picker",
             locals:  { profiles: s.profiles, state: "form", error: nil })
  end

  def create
    s = store
    params_h = profile_params
    s.save(**params_h)

    # Then connect — the button label promises "save & connect". If the connect
    # fails (bad credentials, network), the profile is still saved; user sees
    # the error in the picker and can retry from the list.
    begin
      s.client_for(params_h[:name])
    rescue StandardError => e
      return render turbo_stream: turbo_stream.replace("sql_connection_picker",
               partial: "workbench/sql/connection_picker",
               locals:  { profiles: s.profiles, state: "list", error: "saved profile, but connect failed: #{e.message}" })
    end

    profile = s.find(params_h[:name])
    session[:sql_workbench] = {
      connection:      profile[:name],
      database:        profile[:default_database],
      write_mode:      profile[:default_mode],
      session_limit:   500,
      session_timeout: 30
    }
    render turbo_stream: turbo_stream.replace("sql_pane",
             partial: "workbench/sql/pane",
             locals:  { state: session[:sql_workbench], profiles: s.profiles, run: nil, error: nil })
  end

  def update
    s = store
    existing = s.find(params[:name]) or return head(:not_found)

    merged = {
      name:             params[:name],
      host:             params.dig(:profile, :host)             || existing[:host],
      port:             params.dig(:profile, :port).presence&.to_i || existing[:port],
      user:             params.dig(:profile, :user)             || existing[:user],
      password:         params.dig(:profile, :password).presence || s.password_for(params[:name]),
      default_database: params.dig(:profile, :default_database) || existing[:default_database],
      default_mode:     params.dig(:profile, :default_mode)     || existing[:default_mode],
      tls_mode:         params.dig(:profile, :tls_mode)         || existing[:tls_mode]
    }
    s.save(**merged)
    render turbo_stream: turbo_stream.replace("sql_connection_picker",
             partial: "workbench/sql/connection_picker",
             locals:  { profiles: s.profiles, state: "list", error: nil })
  end

  def destroy
    s = store
    s.disconnect(params[:name])
    s.delete(params[:name])
    render turbo_stream: turbo_stream.replace("sql_connection_picker",
             partial: "workbench/sql/connection_picker",
             locals:  { profiles: s.profiles, state: "list", error: nil })
  end

  private

  def store
    ToolHarness::Sql::ConnectionStore.new
  end

  def profile_params
    p = params.require(:profile).permit(:name, :host, :port, :user, :password,
                                        :default_database, :default_mode, :tls_mode).to_h.symbolize_keys
    p[:port] = p[:port].to_i
    p
  end
end
