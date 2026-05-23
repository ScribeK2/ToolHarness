require "test_helper"
require "tool_harness/sql/runner"
require_relative "../../../support/fake_mysql2_client"

class ToolHarness::Sql::RunnerTest < ActiveSupport::TestCase
  R = ToolHarness::Sql::Runner

  setup do
    FakeMysql2Client.reset!
    @client = FakeMysql2Client.new({})
  end

  def runner(opts = {})
    R.new(
      client:        @client,
      profile_name:  opts[:profile_name]   || "prod",
      database:      opts[:database]       || "ops",
      write_mode:    opts[:write_mode]     || :ro,
      session_limit: opts[:session_limit]  || 500,
      timeout:       opts[:timeout]        || 30,
      confirmed:     opts.fetch(:confirmed, false)
    )
  end

  test "read query passes gate, runs with as: :array, returns normalized result" do
    FakeMysql2Client.next_result = make_result(
      columns: %w[id domain], rows: [[1, "example.com"], [2, "x.com"]]
    )
    out = runner.execute("SELECT id, domain FROM domains")
    assert out.success?
    assert_equal %w[id domain], out.columns
    assert_equal 2, out.row_count
    assert_equal 500, out.applied_limit
    assert_equal "SELECT id, domain FROM domains LIMIT 500", @client.queries.last
  end

  test "ro mode blocks write_safe with a clear error" do
    out = runner(write_mode: :ro).execute("UPDATE domains SET status = 'x' WHERE id = 1")
    refute out.success?
    assert_equal "WRITE_BLOCKED", out.error_code
    assert_match(/:w on/, out.error_message)
    assert_empty @client.queries
  end

  test "rw mode runs write_safe and reports rows_affected" do
    FakeMysql2Client.next_result = make_result(columns: [], rows: [], affected_rows: 42)
    out = runner(write_mode: :rw).execute("UPDATE domains SET status = 'x' WHERE id = 1")
    assert out.success?
    assert_equal 42, out.write_affected
    refute_nil @client.queries.last
  end

  test "rw mode requires :confirmed for write_dangerous" do
    out = runner(write_mode: :rw, confirmed: false).execute("DROP TABLE domains")
    refute out.success?
    assert_equal "CONFIRM_REQUIRED", out.error_code
    assert_empty @client.queries
  end

  test "rw mode runs write_dangerous when confirmed" do
    FakeMysql2Client.next_result = make_result(columns: [], rows: [])
    out = runner(write_mode: :rw, confirmed: true).execute("DROP TABLE domains")
    assert out.success?
  end

  test "unknown is always confirm-required" do
    out = runner(write_mode: :rw).execute("BANANA stuff")
    refute out.success?
    assert_equal "CONFIRM_REQUIRED", out.error_code
  end

  test "Mysql2::Error surfaces with code + message" do
    FakeMysql2Client.next_error = StubMysql2Error.new(1146, "Table doesn't exist")
    out = runner.execute("SELECT * FROM nope")
    refute out.success?
    assert_equal 1146, out.error_code
    assert_match(/Table doesn't exist/, out.error_message)
  end

  test "retries once on ER_SERVER_GONE_AWAY then propagates if still failing" do
    FakeMysql2Client.next_error = StubMysql2Error.new(2006, "gone away")
    @reconnect_count = 0
    runner_obj = runner
    runner_obj.define_singleton_method(:reconnect!) { @reconnect_count = (@reconnect_count || 0) + 1; @client }
    out = runner_obj.execute("SELECT 1")
    refute out.success?
    assert_equal 2006, out.error_code
  end

  private

  # Minimal stand-ins so we don't depend on the real Mysql2 gem in unit tests.
  class StubResult
    attr_reader :columns, :rows, :affected_rows
    def initialize(columns:, rows:, affected_rows: 0)
      @columns       = columns
      @rows          = rows
      @affected_rows = affected_rows
    end
    def each(&blk) = @rows.each(&blk)
    def to_a       = @rows
    def size       = @rows.size
    def fields     = @columns
  end

  class StubMysql2Error < StandardError
    attr_reader :error_number
    def initialize(code, message)
      super(message)
      @error_number = code
    end
  end

  def make_result(columns:, rows:, affected_rows: 0)
    StubResult.new(columns: columns, rows: rows, affected_rows: affected_rows)
  end
end
