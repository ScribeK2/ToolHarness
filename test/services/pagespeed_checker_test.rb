require "test_helper"

class PagespeedCheckerTest < ActiveSupport::TestCase
  def check_with(status:, body:, error: nil, **opts)
    c = PagespeedChecker.new("https://example.com/", strategy: "mobile", key: opts[:key])
    captured = {}
    seam = lambda do |url|
      captured[:url] = url
      { status: status, body: body, error: error }
    end
    result = c.stub(:http_get_json, seam) { c.check }
    [result, captured[:url]]
  end

  OK_BODY = { "lighthouseResult" => { "requestedUrl" => "https://example.com/" } }.freeze

  test "builds the PSI URL with url, strategy and category params" do
    _r, url = check_with(status: 200, body: OK_BODY)
    assert_includes url, "https://www.googleapis.com/pagespeedonline/v5/runPagespeed"
    assert_includes url, "url=https%3A%2F%2Fexample.com%2F"
    assert_includes url, "strategy=mobile"
    assert_includes url, "category=performance"
    assert_not_includes url, "key="
  end

  test "appends the API key when one is supplied" do
    _r, url = check_with(status: 200, body: OK_BODY, key: "abc123")
    assert_includes url, "key=abc123"
  end

  test "200 with a lighthouseResult is success and returns the body" do
    r, _ = check_with(status: 200, body: OK_BODY)
    assert r[:success]
    assert_equal OK_BODY, r[:body]
  end

  test "200 but a Lighthouse runtimeError is a failure with the error message" do
    body = { "lighthouseResult" => { "runtimeError" =>
              { "code" => "NO_FCP", "message" => "The page did not paint any content." } } }
    r, _ = check_with(status: 200, body: body)
    assert_not r[:success]
    assert_match(/did not paint/i, r[:error])
  end

  test "429 maps to a quota message that points at the Credentials tool" do
    r, _ = check_with(status: 429, body: { "error" => { "message" => "Quota exceeded" } })
    assert_not r[:success]
    assert_match(/quota/i, r[:error])
    assert_match(/API key/i, r[:error])
  end

  test "4xx/5xx surfaces the PSI error.message" do
    body = { "error" => { "message" => "Lighthouse returned error: ERRORED_DOCUMENT_REQUEST." } }
    r, _ = check_with(status: 400, body: body)
    assert_not r[:success]
    assert_match(/ERRORED_DOCUMENT_REQUEST/, r[:error])
  end

  test "network failure (status 0) is a failure" do
    r, _ = check_with(status: 0, body: nil, error: "execution expired")
    assert_not r[:success]
    assert_match(/execution expired/, r[:error])
  end
end
