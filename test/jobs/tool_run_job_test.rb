require "test_helper"

class ToolRunJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
  end

  def teardown
    @added_keys&.each { |k| ToolHarness::Registry.tools.delete(k) }
  end

  test "successful run: pending → processing → completed, ToolRun fields populated" do
    register_fake_tool(:fake_ok, success: true, summary: "fake summary", data: { foo: 1 })

    run = ToolRun.create_pending!(
      user: @user,
      tool_class: ToolHarness::Registry.find_tool(:fake_ok),
      params: { domain: "example.com" }
    )
    assert_equal "pending", run.status

    ToolRunJob.perform_now(run.id)
    run.reload

    assert_equal "completed", run.status
    assert run.success
    assert_equal "fake summary",   run.summary
    assert_equal({ "foo" => 1 },   run.result_data)
    assert_not_nil run.started_at
    assert_not_nil run.completed_at
    assert run.execution_time >= 0
  end

  test "failed inner Result marks the ToolRun failed" do
    register_fake_tool(:fake_failure, success: false, summary: "boom", error: "downstream broke")

    run = ToolRun.create_pending!(
      user: @user,
      tool_class: ToolHarness::Registry.find_tool(:fake_failure),
      params: { domain: "example.com" }
    )

    ToolRunJob.perform_now(run.id)
    run.reload

    assert_equal "failed", run.status
    assert_not run.success
    assert_equal "downstream broke", run.error
    assert_equal "boom", run.summary
  end

  test "unknown tool_key: status becomes failed with a clear error" do
    run = @user.tool_runs.create!(
      tool_key:  "ghost_tool",
      tool_name: "Ghost",
      category:  "fake",
      input:     {},
      status:    "pending"
    )

    ToolRunJob.perform_now(run.id)
    run.reload

    assert_equal "failed", run.status
    assert_match(/Unknown tool/, run.error)
    assert_not_nil run.completed_at
  end

  test "broadcast failure does not propagate or mark the run failed" do
    register_fake_tool(:fake_for_broadcast, success: true, summary: "ok")
    run = ToolRun.create_pending!(
      user: @user,
      tool_class: ToolHarness::Registry.find_tool(:fake_for_broadcast),
      params: { domain: "example.com" }
    )

    # Force the broadcast to raise. The job's rescue should swallow it cleanly.
    Turbo::StreamsChannel.stub :broadcast_replace_to, ->(*_args, **_kwargs) { raise "stream went away" } do
      assert_nothing_raised { ToolRunJob.perform_now(run.id) }
    end

    run.reload
    assert_equal "completed", run.status, "run should still be marked completed despite broadcast failure"
    assert run.success
  end

  private

  # Register a stand-in tool in the registry that returns a canned Result,
  # and track its key for teardown cleanup.
  def register_fake_tool(key, success:, summary: nil, data: {}, error: nil)
    @added_keys ||= []
    @added_keys << key
    full_name = "Tools::#{key.to_s.camelize}"

    klass = Class.new
    klass.define_singleton_method(:name)       { full_name }
    klass.class_eval { include ToolHarness::Tool }
    klass.define_singleton_method(:tool_name)  { full_name.demodulize.titleize }
    klass.define_singleton_method(:category)   { :test }
    klass.define_singleton_method(:input_type) { :domain }
    klass.define_singleton_method(:cacheable?) { false }
    klass.define_method(:execute) do |_params|
      ToolHarness::Result.new(success: success, tool: full_name, summary: summary, data: data, error: error)
    end
    klass
  end

  def assert_nothing_raised
    yield
  rescue => e
    flunk "expected no exception, got #{e.class}: #{e.message}"
  end
end
