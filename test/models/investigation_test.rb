require "test_helper"

class InvestigationTest < ActiveSupport::TestCase
  test "requires domain and track" do
    inv = Investigation.new(domain: "", track: "")
    assert_not inv.valid?
    assert inv.errors[:domain].any?
    assert inv.errors[:track].any?
  end

  test "owns ordered tool_runs and exposes terminal?" do
    inv = Investigation.create!(domain: "example.com", track: "orientation", status: "running")
    b = inv.tool_runs.create!(tool_key: "dns_lookup",   tool_name: "DNS",   category: "dns",    status: "completed", step_order: 1)
    a = inv.tool_runs.create!(tool_key: "whois_lookup", tool_name: "WHOIS", category: "domain", status: "pending",   step_order: 0)

    assert_equal [a, b], inv.tool_runs.to_a   # ordered by step_order
    assert_not inv.all_steps_terminal?         # one still pending
    a.update!(status: "failed")
    assert inv.reload.all_steps_terminal?      # completed + failed both terminal
  end

  test "running? reflects status" do
    assert Investigation.new(status: "running").running?
    assert_not Investigation.new(status: "completed").running?
  end

  test "all_steps_terminal? is false with no runs" do
    inv = Investigation.create!(domain: "example.com", track: "orientation", status: "running")
    assert_not inv.all_steps_terminal?
  end

  test "enforce_retention_cap! nullifies child runs of purged investigations without raising" do
    old = Investigation.create!(domain: "old.com", track: "orientation", status: "completed")
    child = old.tool_runs.create!(tool_key: "dns_lookup", tool_name: "DNS", category: "dns", status: "completed", step_order: 0)
    Investigation.create!(domain: "new.com", track: "orientation", status: "running")

    purged = nil
    assert_nothing_raised { purged = Investigation.enforce_retention_cap!(cap: 1) }
    assert_equal 1, purged
    assert_not Investigation.exists?(old.id), "oldest investigation should be purged"
    assert ToolRun.exists?(child.id), "child run should survive the purge"
    assert_nil child.reload.investigation_id, "child run's investigation_id should be nullified"
  end
end
