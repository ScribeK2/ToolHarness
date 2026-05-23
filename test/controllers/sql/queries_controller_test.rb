require "test_helper"
require "tmpdir"
require_relative "../../support/fake_mysql2_client"

class Sql::QueriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @tmp_config = Dir.mktmpdir("th-sql-cfg-")
    @prev_env   = ENV["TOOLHARNESS_CONFIG_DIR"]
    ENV["TOOLHARNESS_CONFIG_DIR"] = @tmp_config
    FakeMysql2Client.reset!
    ToolHarness::Sql::ConnectionStore.client_factory = ->(opts) { FakeMysql2Client.new(opts) }
    s = ToolHarness::Sql::ConnectionStore.new
    s.save(name: "x", host: "h", port: 4000, user: "u", password: "p",
           default_database: "d", default_mode: "ro", tls_mode: "prefer")
    post sql_session_path, params: { profile_name: "x" }
  end

  teardown do
    ENV["TOOLHARNESS_CONFIG_DIR"] = @prev_env
    FileUtils.remove_entry(@tmp_config)
    ToolHarness::Sql::ConnectionStore.client_factory = nil
    ToolHarness::Sql::ConnectionStore.pool = {}
  end

  test "POST query persists a ToolRun and renders the result via turbo_stream" do
    FakeMysql2Client.next_result = stub_result(columns: %w[id], rows: [[1], [2]])
    assert_difference("ToolRun.count", 1) do
      post sql_queries_path, params: { sql: "SELECT id FROM t" }
    end
    assert_response :success
    run = ToolRun.last
    assert_equal "sql_workbench", run.tool_key
    assert_equal "SELECT id FROM t LIMIT 500", run.input["sql"]
    assert_equal "x",   run.input["connection"]
    assert_equal "d",   run.input["database"]
    assert_equal 500,   run.result_data["applied_limit"]
    assert_equal 2,     run.result_data["row_count"]
    assert_equal %w[id], run.result_data["columns"]
    assert_equal "completed", run.status
  end

  test "blocked write produces a failed ToolRun with WRITE_BLOCKED error" do
    post sql_queries_path, params: { sql: "DELETE FROM domains" }
    assert_response :success
    run = ToolRun.last
    assert_equal "failed", run.status
    assert_match(/write blocked/, run.error)
  end

  test "confirm_required emits a confirm overlay turbo_stream (no ToolRun yet)" do
    patch sql_session_path, params: { write_mode: "rw" }
    assert_no_difference("ToolRun.count") do
      post sql_queries_path, params: { sql: "DROP TABLE domains" }
    end
    assert_response :success
    assert_match(/sql_confirm_overlay/, response.body)
  end

  test "confirmed=true runs the dangerous statement and writes a successful ToolRun" do
    patch sql_session_path, params: { write_mode: "rw" }
    FakeMysql2Client.next_result = stub_result(columns: [], rows: [], affected_rows: 0)
    assert_difference("ToolRun.count", 1) do
      post sql_queries_path, params: { sql: "DROP TABLE domains", confirmed: "true" }
    end
    assert_equal "completed", ToolRun.last.status
  end

  private

  def stub_result(columns:, rows:, affected_rows: 0)
    Struct.new(:fields, :to_a, :size, :affected_rows).new(columns, rows, rows.size, affected_rows).tap do |s|
      def s.each(&blk) = to_a.each(&blk)
    end
  end
end
