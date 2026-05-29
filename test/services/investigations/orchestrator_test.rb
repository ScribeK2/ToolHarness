require "test_helper"

class Investigations::OrchestratorTest < ActiveJob::TestCase
  test "creates a running investigation with three pending child runs and enqueues a job per child" do
    inv = nil
    assert_difference -> { ToolRun.count }, 3 do
      assert_enqueued_jobs 3, only: ToolRunJob do
        inv = Investigations::Orchestrator.start(domain: "example.com", track_key: "orientation")
      end
    end

    assert_equal "running", inv.status
    assert_equal "example.com", inv.domain
    assert_not_nil inv.started_at

    runs = inv.tool_runs.to_a
    assert_equal %w[whois_lookup dns_lookup hosting_diagnostic], runs.map(&:tool_key)
    assert_equal [0, 1, 2], runs.map(&:step_order)
    assert runs.all? { |r| r.status == "pending" }
    assert runs.all? { |r| r.input["domain"] == "example.com" }
  end

  test "stores ticket_ref when provided" do
    inv = Investigations::Orchestrator.start(domain: "example.com", ticket_ref: "TCK-42")
    assert_equal "TCK-42", inv.ticket_ref
  end

  test "email_delivery creates six pending runs but enqueues only the four independent probes" do
    inv = nil
    assert_difference -> { ToolRun.count }, 6 do
      assert_enqueued_jobs 4, only: ToolRunJob do
        inv = Investigations::Orchestrator.start(domain: "example.com", track_key: "email_delivery")
      end
    end

    runs = inv.tool_runs.to_a
    assert_equal %w[dns_lookup spf_check dkim_check dmarc_check hosting_diagnostic blacklist], runs.map(&:tool_key)
    assert runs.all? { |r| r.status == "pending" }

    # Both dependent probes (hosting_diagnostic, blacklist) are left unqueued for the scheduler.
    %w[hosting_diagnostic blacklist].each do |key|
      step = runs.find { |r| r.tool_key == key }
      assert_equal "pending", step.status
      assert_equal "example.com", step.input["domain"]
    end
  end
end
