require "test_helper"

class ToolRunTest < ActiveSupport::TestCase
  # ---- validations ----

  test "valid with required fields" do
    run = ToolRun.new(
      tool_key: "dns_lookup", tool_name: "DNS Lookup",
      category: "dns", status: "pending"
    )
    assert run.valid?, run.errors.full_messages.inspect
  end

  test "requires tool_key, tool_name, category" do
    run = ToolRun.new(status: "pending")
    assert_not run.valid?
    assert_includes run.errors[:tool_key], "can't be blank"
    assert_includes run.errors[:tool_name], "can't be blank"
    assert_includes run.errors[:category], "can't be blank"
  end

  # ---- scopes ----

  test "recent orders newest first" do
    older = ToolRun.create!(tool_key: "a", tool_name: "A", category: "x", status: "completed", success: true, created_at: 2.days.ago)
    newer = ToolRun.create!(tool_key: "b", tool_name: "B", category: "x", status: "completed", success: true, created_at: 1.hour.ago)

    recent = ToolRun.recent.to_a
    assert_equal newer, recent.first
    assert_equal older, recent.last
  end

  test "successful and failed_runs scopes" do
    ok  = ToolRun.create!(tool_key: "a", tool_name: "A", category: "x", status: "completed", success: true)
    bad = ToolRun.create!(tool_key: "b", tool_name: "B", category: "x", status: "failed", success: false)

    assert_includes ToolRun.successful, ok
    assert_not_includes ToolRun.successful, bad
    assert_includes ToolRun.failed_runs, bad
    assert_not_includes ToolRun.failed_runs, ok
  end

  test "for_category and for_tool filters" do
    dns_run = ToolRun.create!(tool_key: "dns_lookup", tool_name: "DNS Lookup", category: "dns", status: "completed", success: true)
    ssl_run = ToolRun.create!(tool_key: "ssl_inspect", tool_name: "SSL Inspect", category: "ssl", status: "completed", success: true)

    assert_includes     ToolRun.for_category(:dns), dns_run
    assert_not_includes ToolRun.for_category(:dns), ssl_run
    assert_includes     ToolRun.for_tool("dns_lookup"), dns_run
    assert_not_includes ToolRun.for_tool("dns_lookup"), ssl_run
  end

  test "search_input matches input_summary substring; passthrough on blank" do
    match    = ToolRun.create!(tool_key: "a", tool_name: "A", category: "x", status: "completed", success: true, input_summary: "example.com")
    no_match = ToolRun.create!(tool_key: "b", tool_name: "B", category: "x", status: "completed", success: true, input_summary: "other.org")

    assert_includes     ToolRun.search_input("example"), match
    assert_not_includes ToolRun.search_input("example"), no_match
    assert_equal ToolRun.count, ToolRun.search_input("").count
    assert_equal ToolRun.count, ToolRun.search_input(nil).count
  end

  # ---- build_input_summary class helper ----

  test "build_input_summary picks the first matching identifier" do
    assert_equal "example.com",       ToolRun.build_input_summary(domain: "example.com")
    assert_equal "user@example.com",  ToolRun.build_input_summary(email: "user@example.com")
    assert_equal "1.2.3.4",           ToolRun.build_input_summary(ip: "1.2.3.4")
    assert_equal "TH-123",            ToolRun.build_input_summary(ticket_id: "TH-123")
  end

  test "build_input_summary appends port" do
    assert_equal "example.com:8443", ToolRun.build_input_summary(domain: "example.com", port: 8443)
  end

  test "build_input_summary handles bulk shape" do
    out = ToolRun.build_input_summary(domains: "a.com\nb.com\nc.com", tool_key: "dns_lookup")
    assert_equal "3 domains via dns_lookup", out

    out = ToolRun.build_input_summary(domains: "single.com", tool_key: "dns_lookup")
    assert_equal "1 domain via dns_lookup", out
  end

  test "build_input_summary returns nil when nothing matches" do
    assert_nil ToolRun.build_input_summary({})
    assert_nil ToolRun.build_input_summary(foo: "bar")
  end

  # ---- create_pending! / apply_result! lifecycle ----

  test "create_pending! creates a row in pending state from a tool class" do
    run = ToolRun.create_pending!(tool_class: Tools::DnsLookup, params: { domain: "example.com" })

    assert run.persisted?
    assert_equal "pending", run.status
    assert_equal "dns_lookup", run.tool_key
    assert_equal "DNS Lookup", run.tool_name
    assert_equal "dns", run.category
    assert_equal "domain", run.input_type
    assert_equal "example.com", run.input_summary
    assert_equal({ "domain" => "example.com" }, run.input)
  end

  test "apply_result! merges a Result and flips status to completed/failed" do
    run    = ToolRun.create_pending!(tool_class: Tools::DnsLookup, params: { domain: "example.com" })
    result = ToolHarness::Result.new(
      success: true,
      tool: "DNS Lookup",
      data: { a_records: ["1.2.3.4"] },
      issues: [{ severity: "info", title: "x" }],
      summary: "resolved",
      execution_time: 0.123
    )

    run.apply_result!(result, started_at: 1.second.ago, completed_at: Time.current)

    assert_equal "completed",  run.status
    assert run.success
    assert_equal({ "a_records" => ["1.2.3.4"] }, run.result_data)
    assert_equal 1, run.issues.size
    assert_equal "resolved", run.summary
    assert_in_delta 0.123, run.execution_time, 0.0001
    assert_not_nil run.started_at
    assert_not_nil run.completed_at
  end

  test "apply_result! with failed Result marks status failed" do
    run    = ToolRun.create_pending!(tool_class: Tools::DnsLookup, params: { domain: "example.com" })
    result = ToolHarness::Result.new(success: false, tool: "DNS Lookup", error: "boom")

    run.apply_result!(result)

    assert_equal "failed", run.status
    assert_not run.success
    assert_equal "boom", run.error
  end

  # ---- tool_class instance method ----

  test "#tool_class resolves via the registry from tool_key" do
    ToolHarness::Registry.auto_discover!
    run = ToolRun.new(tool_key: "dns_lookup", tool_name: "X", category: "dns")
    assert_equal Tools::DnsLookup, run.tool_class
  end

  test "#tool_class returns nil when tool_key is unknown" do
    run = ToolRun.new(tool_key: "no_such_tool", tool_name: "X", category: "dns")
    assert_nil run.tool_class
  end
end
