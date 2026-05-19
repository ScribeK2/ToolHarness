class Sql::ProfilesController < ApplicationController
  def create
    s = store
    s.save(**profile_params)
    render turbo_stream: turbo_stream.replace("sql_connection_picker",
             partial: "workbench/sql/connection_picker",
             locals:  { profiles: s.profiles, state: "list", error: nil })
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
