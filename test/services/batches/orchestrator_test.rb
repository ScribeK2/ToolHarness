require "test_helper"

class Batches::OrchestratorTest < ActiveJob::TestCase
  test "start creates a running batch + one pending child per domain and enqueues a job each" do
    batch = nil
    assert_difference -> { ToolRun.count }, 2 do
      assert_enqueued_jobs 2, only: ToolRunJob do
        batch = Batches::Orchestrator.start(tool_key: "dns_lookup", domains: "a.com\nb.com")
      end
    end
    assert_equal "running", batch.status
    assert_equal 2, batch.domain_count
    runs = batch.tool_runs.to_a
    assert_equal %w[a.com b.com], runs.map { |r| r.input["domain"] }
    assert runs.all? { |r| r.status == "pending" && r.tool_key == "dns_lookup" }
    assert_equal [0, 1], runs.map(&:step_order)
  end

  test "parse dedupes, regex-filters, and caps at 50" do
    batch = Batches::Orchestrator.start(tool_key: "dns_lookup", domains: "a.com, a.com  not a domain\nb.com")
    assert_equal %w[a.com b.com], batch.tool_runs.map { |r| r.input["domain"] }
  end

  test "unknown tool raises ArgumentError and creates nothing" do
    assert_no_difference -> { Batch.count } do
      assert_raises(ArgumentError) { Batches::Orchestrator.start(tool_key: "ghost", domains: "a.com") }
    end
  end

  test "non-domain-input tool raises ArgumentError" do
    assert_raises(ArgumentError) { Batches::Orchestrator.start(tool_key: "sql_workbench", domains: "a.com") }
  end

  test "empty/invalid domain list raises ArgumentError" do
    assert_raises(ArgumentError) { Batches::Orchestrator.start(tool_key: "dns_lookup", domains: "   ") }
  end
end
