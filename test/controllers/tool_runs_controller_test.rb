require "test_helper"

class ToolRunsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @other_user = users(:two)
    sign_in @user
  end

  # ---- create ----

  test "POST creates a pending ToolRun and enqueues ToolRunJob" do
    assert_difference -> { @user.tool_runs.count }, 1 do
      assert_enqueued_with(job: ToolRunJob) do
        post tool_run_create_path(:dns_lookup), params: { tool_run: { domain: "example.com" } }
      end
    end

    run = @user.tool_runs.order(created_at: :desc).first
    assert_equal "dns_lookup", run.tool_key
    assert_equal "pending",    run.status
    assert_equal "example.com", run.input["domain"]
    assert_redirected_to tool_run_path(run)
  end

  test "POST permits only declared form_fields, ignoring extras" do
    post tool_run_create_path(:dns_lookup),
      params: { tool_run: { domain: "example.com", malicious: "x" } }

    run = @user.tool_runs.order(created_at: :desc).first
    assert_equal({ "domain" => "example.com" }, run.input)
  end

  test "POST to unknown tool_key returns 404" do
    post tool_run_create_path(:nonexistent_tool), params: { tool_run: { domain: "example.com" } }
    assert_response :not_found
  end

  # ---- show ----

  test "GET /tool_runs/:id renders the result page for own run" do
    run = ToolRun.create_pending!(user: @user, tool_class: Tools::DnsLookup, params: { domain: "example.com" })
    get tool_run_url(run)
    assert_response :success
    assert_select "h1", text: /DNS Lookup/
  end

  test "GET /tool_runs/:id returns 404 for another user's run" do
    run = ToolRun.create_pending!(user: @other_user, tool_class: Tools::DnsLookup, params: { domain: "example.com" })
    get tool_run_url(run)
    assert_response :not_found
  end

  # ---- index + filters ----

  test "GET /tool_runs lists only the current user's runs, newest first" do
    older  = create_run(user: @user, tool_key: "dns_lookup", category: "dns",  created_at: 2.days.ago)
    newer  = create_run(user: @user, tool_key: "ssl_inspect", category: "ssl", created_at: 1.hour.ago)
    other  = create_run(user: @other_user, tool_key: "dns_lookup", category: "dns")

    get tool_runs_url
    assert_response :success
    assert_select "a[href=?]", tool_run_path(newer)
    assert_select "a[href=?]", tool_run_path(older)
    assert_select "a[href=?]", tool_run_path(other), count: 0
  end

  test "GET /tool_runs?category=dns filters to that category" do
    dns_run = create_run(user: @user, tool_key: "dns_lookup", category: "dns")
    ssl_run = create_run(user: @user, tool_key: "ssl_inspect", category: "ssl")

    get tool_runs_url(category: "dns")
    assert_select "a[href=?]", tool_run_path(dns_run)
    assert_select "a[href=?]", tool_run_path(ssl_run), count: 0
  end

  test "GET /tool_runs?tool=dns_lookup filters to that tool" do
    dns_run = create_run(user: @user, tool_key: "dns_lookup", category: "dns")
    ssl_run = create_run(user: @user, tool_key: "ssl_inspect", category: "ssl")

    get tool_runs_url(tool: "dns_lookup")
    assert_select "a[href=?]", tool_run_path(dns_run)
    assert_select "a[href=?]", tool_run_path(ssl_run), count: 0
  end

  test "GET /tool_runs?filter=failed shows only failed runs" do
    ok_run  = create_run(user: @user, tool_key: "dns_lookup", category: "dns", success: true)
    bad_run = create_run(user: @user, tool_key: "dns_lookup", category: "dns", success: false, status: "failed")

    get tool_runs_url(filter: "failed")
    assert_select "a[href=?]", tool_run_path(bad_run)
    assert_select "a[href=?]", tool_run_path(ok_run), count: 0
  end

  test "GET /tool_runs?q=substr filters by input_summary substring" do
    run_a = create_run(user: @user, tool_key: "dns_lookup", category: "dns", input_summary: "example.com")
    run_b = create_run(user: @user, tool_key: "dns_lookup", category: "dns", input_summary: "other.org")

    get tool_runs_url(q: "example")
    assert_select "a[href=?]", tool_run_path(run_a)
    assert_select "a[href=?]", tool_run_path(run_b), count: 0
  end

  test "/tool_runs requires authentication" do
    sign_out @user
    get tool_runs_url
    assert_redirected_to new_user_session_path
  end

  private

  def create_run(user:, tool_key:, category:, success: true, status: "completed", created_at: Time.current, input_summary: "example.com")
    ToolRun.create!(
      user: user, tool_key: tool_key, tool_name: tool_key.humanize, category: category,
      input_type: "domain", status: status, success: success,
      input: { domain: input_summary }, input_summary: input_summary,
      created_at: created_at
    )
  end
end
