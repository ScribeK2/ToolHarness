require "test_helper"
require "tmpdir"

class SqlConfigWarningBannerTest < ActionDispatch::IntegrationTest
  setup do
    @tmp_config = Dir.mktmpdir("th-sql-cfg-")
    @prev_env   = ENV["TOOLHARNESS_CONFIG_DIR"]
    ENV["TOOLHARNESS_CONFIG_DIR"] = @tmp_config
  end

  teardown do
    ENV["TOOLHARNESS_CONFIG_DIR"] = @prev_env
    FileUtils.remove_entry(@tmp_config)
    ToolHarness::Sql::ConnectionStore.pool = {}
  end

  test "malformed connections.yml surfaces a warning banner in the SQL pane" do
    File.write(File.join(@tmp_config, "connections.yml"), "foo: bar: baz\n")
    get "/workbench", params: { tool: "sql_workbench" }
    assert_response :success
    assert_match(/id="sql_config_warning"/, response.body)
    assert_match(/connections\.yml/, response.body)
  end

  test "malformed recipes.yml surfaces a warning banner in the SQL pane" do
    File.write(File.join(@tmp_config, "recipes.yml"), "foo: bar: baz\n")
    get "/workbench", params: { tool: "sql_workbench" }
    assert_response :success
    assert_match(/id="sql_config_warning"/, response.body)
    assert_match(/recipes\.yml/, response.body)
  end

  test "no warning banner when config files are valid or absent" do
    get "/workbench", params: { tool: "sql_workbench" }
    assert_response :success
    assert_no_match(/id="sql_config_warning"/, response.body)
  end
end
