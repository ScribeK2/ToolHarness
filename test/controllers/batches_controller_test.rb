require "test_helper"

class BatchesControllerTest < ActionDispatch::IntegrationTest
  test "POST create starts a batch and redirects to its page" do
    assert_difference -> { Batch.count }, 1 do
      post batches_path, params: { tool_key: "dns_lookup", domains: "a.com\nb.com" }
    end
    batch = Batch.order(:created_at).last
    assert_redirected_to batch_path(batch)
    assert_equal 2, batch.tool_runs.count
  end

  test "POST create with no valid domains redirects back with an alert" do
    assert_no_difference -> { Batch.count } do
      post batches_path, params: { tool_key: "dns_lookup", domains: "   " }
    end
    assert_response :redirect
  end

  test "GET show renders the live table with a row per child and the aggregate" do
    batch = Batch.create!(tool_key: "dns_lookup", status: "running", domain_count: 1)
    batch.tool_runs.create!(tool_key: "dns_lookup", tool_name: "DNS", category: "dns",
                            status: "completed", success: true, input: { "domain" => "a.com" },
                            input_summary: "a.com", summary: "Resolves.", step_order: 0)
    get batch_path(batch)
    assert_response :success
    assert_select "#batch_table_#{batch.id}"
    assert_select "#batch_aggregate_#{batch.id}"
    assert_match(/a\.com/, response.body)
  end
end
