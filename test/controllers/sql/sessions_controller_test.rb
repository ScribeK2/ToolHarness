require "test_helper"
require "tmpdir"
require_relative "../../support/fake_mysql2_client"

class Sql::SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @tmp_config = Dir.mktmpdir("th-sql-cfg-")
    @prev_env   = ENV["TOOLHARNESS_CONFIG_DIR"]
    ENV["TOOLHARNESS_CONFIG_DIR"] = @tmp_config
    FakeMysql2Client.reset!
    ToolHarness::Sql::ConnectionStore.client_factory = ->(opts) { FakeMysql2Client.new(opts) }
    store = ToolHarness::Sql::ConnectionStore.new
    store.save(name: "x", host: "h", port: 4000, user: "u", password: "p",
               default_database: "d", default_mode: "ro", tls_mode: "prefer")
  end

  teardown do
    ENV["TOOLHARNESS_CONFIG_DIR"] = @prev_env
    FileUtils.remove_entry(@tmp_config)
    ToolHarness::Sql::ConnectionStore.client_factory = nil
    ToolHarness::Sql::ConnectionStore.pool = {}
  end

  test "POST connect by profile_name sets session and opens a client" do
    post sql_session_path, params: { profile_name: "x" }
    assert_response :success
    assert_equal "x", session[:sql_workbench][:connection]
    assert_equal "d", session[:sql_workbench][:database]
    assert_equal "ro", session[:sql_workbench][:write_mode]
    assert_equal 1, FakeMysql2Client.instances.size
  end

  test "DELETE disconnect clears session and closes the client" do
    post sql_session_path, params: { profile_name: "x" }
    delete sql_session_path
    assert_response :success
    assert_nil session[:sql_workbench]
    assert FakeMysql2Client.instances.last.closed
  end

  test "PATCH update changes database / write_mode / session_limit / session_timeout" do
    post sql_session_path, params: { profile_name: "x" }

    patch sql_session_path, params: { database: "neon" }
    assert_equal "neon", session[:sql_workbench][:database]

    patch sql_session_path, params: { write_mode: "rw" }
    assert_equal "rw", session[:sql_workbench][:write_mode]

    patch sql_session_path, params: { session_limit: "1000" }
    assert_equal 1000, session[:sql_workbench][:session_limit]

    patch sql_session_path, params: { session_timeout: "60" }
    assert_equal 60, session[:sql_workbench][:session_timeout]
  end

  test "POST ad-hoc connect (no profile_name) opens a client and sets session" do
    post sql_session_path, params: { host: "10.1.2.3", port: 4000, user: "ro", password: "secret", database: "ops" }
    assert_response :success
    assert_equal "_adhoc", session[:sql_workbench][:connection]
    assert_equal "ops",    session[:sql_workbench][:database]
    assert_equal "ro",     session[:sql_workbench][:write_mode]
    fake = FakeMysql2Client.instances.last
    assert_equal "10.1.2.3", fake.init_opts[:host]
    assert_equal 4000,        fake.init_opts[:port]
    assert_equal "ro",        fake.init_opts[:username]
    assert_equal "secret",    fake.init_opts[:password]
  end

  test "POST ad-hoc with missing host returns picker error" do
    post sql_session_path, params: { user: "ro", password: "p" }
    assert_response :success
    assert_match(/host=/, response.body)
  end
end
