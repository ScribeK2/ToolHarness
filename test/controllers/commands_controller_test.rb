require "test_helper"

class CommandsControllerTest < ActionDispatch::IntegrationTest
  test "POST /commands with :run dispatches a tool run" do
    post "/commands", params: { cmd: "run whois_lookup example.com" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_match /turbo-stream/, response.body
    assert ToolRun.exists?(tool_key: "whois_lookup"), "expected a ToolRun created"
  end

  test "POST /commands with :export returns a stream that points to a downloadable URL" do
    run = ToolRun.create!(tool_key: "whois_lookup", tool_name: "WHOIS", category: "domain",
                          status: "completed", success: true, result_data: { "x" => 1 })
    post "/commands", params: { cmd: "export json", run_id: run.id }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_match /download/i, response.body
  end

  test ":export csv escapes embedded quotes and renders a data URL" do
    run = ToolRun.create!(tool_key: "whois_lookup", tool_name: "WHOIS", category: "domain",
                          status: "completed", success: true,
                          result_data: { "note" => %(she said "hi"), "plain" => "ok" })
    post "/commands", params: { cmd: "export csv", run_id: run.id }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    payload = decode_data_url(response.body)
    assert_equal %(key,value\nnote,"she said ""hi"""\nplain,"ok"), payload
    assert_match %r{toolrun-#{run.id}\.csv}, response.body
  end

  test ":export md renders a markdown payload with heading and bullets" do
    run = ToolRun.create!(tool_key: "whois_lookup", tool_name: "WHOIS", category: "domain",
                          status: "completed", success: true, input_summary: "example.com",
                          result_data: { "registrar" => "IANA" })
    post "/commands", params: { cmd: "export md", run_id: run.id }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    payload = decode_data_url(response.body)
    assert_includes payload, "# WHOIS — example.com"
    assert_includes payload, "- **registrar**: IANA"
    assert_match %r{toolrun-#{run.id}\.md}, response.body
  end

  test ":export with no format falls back to JSON" do
    run = ToolRun.create!(tool_key: "whois_lookup", tool_name: "WHOIS", category: "domain",
                          status: "completed", success: true, result_data: { "x" => 1 })
    post "/commands", params: { cmd: "export", run_id: run.id }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    payload = decode_data_url(response.body)
    parsed = JSON.parse(payload)
    assert_equal run.id, parsed["id"]
    assert_match %r{toolrun-#{run.id}\.json}, response.body
  end

  test ":export with a missing run_id returns a no-current-run error" do
    post "/commands", params: { cmd: "export json", run_id: 999_999 }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_match /no current run to export/i, response.body
  end

  test ":purge without an older= argument returns a usage error" do
    post "/commands", params: { cmd: "purge" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_match /usage: :purge older=&lt;N&gt;d/, response.body
  end

  test ":purge with a malformed older= argument returns a usage error" do
    post "/commands", params: { cmd: "purge older=garbage" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_match /usage: :purge older=&lt;N&gt;d/, response.body
  end

  test ":purge reports the number of deleted runs older than the cutoff" do
    old = ToolRun.create!(tool_key: "whois_lookup", tool_name: "WHOIS", category: "domain",
                          status: "completed", success: true)
    old.update_column(:created_at, 31.days.ago)
    fresh = ToolRun.create!(tool_key: "whois_lookup", tool_name: "WHOIS", category: "domain",
                            status: "completed", success: true)
    post "/commands", params: { cmd: "purge older=30d" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_match /purged 1 runs older than 30d/, response.body
    refute ToolRun.exists?(old.id)
    assert ToolRun.exists?(fresh.id)
  end

  test "POST /commands with an unknown command returns an inline error stream" do
    post "/commands", params: { cmd: "nope" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_match /no command/i, response.body
  end

  test "error_stream escapes HTML characters in the message" do
    post "/commands", params: { cmd: "nope <script>alert(1)</script>" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_no_match /<script>alert\(1\)<\/script>/, response.body
    assert_match    /&lt;script&gt;alert\(1\)&lt;\/script&gt;/, response.body
  end

  test ":investigate starts an investigation and redirects to its page" do
    investigation = nil
    assert_difference -> { Investigation.count }, 1 do
      post commands_path,
        params: { cmd: ":investigate example.com" },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    investigation = Investigation.order(created_at: :desc).first
    assert_redirected_to investigation_path(investigation)
  end

  test ":investigate with no domain reports an error" do
    post commands_path, params: { cmd: ":investigate" },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_match(/cmdline_message/, response.body)
    assert_match(/usage/, response.body)
  end

  private

  # Extracts the URL-encoded payload from a `data:text/plain;charset=utf-8,...`
  # href emitted by dispatch_export and returns the decoded string.
  def decode_data_url(body)
    href = body[/href="data:text\/plain;charset=utf-8,([^"]+)"/, 1]
    refute_nil href, "expected a data: URL in the turbo stream body"
    CGI.unescape(href)
  end
end
