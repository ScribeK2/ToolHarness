require "test_helper"
require "tmpdir"

class Sql::ProfilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @tmp_config = Dir.mktmpdir("th-sql-cfg-")
    @prev_env   = ENV["TOOLHARNESS_CONFIG_DIR"]
    ENV["TOOLHARNESS_CONFIG_DIR"] = @tmp_config
  end

  teardown do
    ENV["TOOLHARNESS_CONFIG_DIR"] = @prev_env
    FileUtils.remove_entry(@tmp_config)
  end

  test "GET new returns the picker in form state" do
    get new_sql_profile_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_match(/profile\[name\]/, response.body)
    assert_match(/profile\[host\]/, response.body)
  end

  test "POST /workbench/sql/profiles creates a profile" do
    post sql_profiles_path, params: {
      profile: { name: "prod-ops", host: "10.1.2.3", port: 4000, user: "ro",
                 password: "secret", default_database: "ops",
                 default_mode: "ro", tls_mode: "prefer" }
    }
    assert_response :success
    store = ToolHarness::Sql::ConnectionStore.new
    p = store.find("prod-ops")
    refute_nil p
    assert_equal "10.1.2.3", p[:host]
    assert_equal "secret",   store.password_for("prod-ops")
  end

  test "DELETE removes a profile" do
    store = ToolHarness::Sql::ConnectionStore.new
    store.save(name: "x", host: "h", port: 4000, user: "u", password: "p",
               default_database: "d", default_mode: "ro", tls_mode: "prefer")

    delete sql_profile_path(name: "x")
    assert_response :success
    assert_nil ToolHarness::Sql::ConnectionStore.new.find("x")
  end

  test "PATCH updates a profile (password only if provided)" do
    store = ToolHarness::Sql::ConnectionStore.new
    store.save(name: "x", host: "h", port: 4000, user: "u", password: "old",
               default_database: "d", default_mode: "ro", tls_mode: "prefer")

    patch sql_profile_path(name: "x"), params: { profile: { host: "h2", password: "" } }
    assert_response :success
    fresh = ToolHarness::Sql::ConnectionStore.new
    assert_equal "h2",  fresh.find("x")[:host]
    assert_equal "old", fresh.password_for("x")  # unchanged
  end
end
