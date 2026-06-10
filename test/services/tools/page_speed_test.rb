require "test_helper"

class Tools::PageSpeedTest < ActiveSupport::TestCase
  OK = { success: true, body: { "lighthouseResult" => {
           "requestedUrl" => "https://example.com/", "finalDisplayedUrl" => "https://example.com/",
           "categories" => { "performance" => { "score" => 0.72 } }, "audits" => {} } } }.freeze

  # Stub CredentialStore.new to return an object whose #secret_for yields `token`.
  def with_key(token, &blk)
    fake = Object.new
    fake.define_singleton_method(:secret_for) { |_id| token }
    ToolHarness::CredentialStore.stub(:new, fake, &blk)
  end

  test "tool metadata: category, partial, select field, path-preserving URL input" do
    assert_equal :web, Tools::PageSpeed.category
    assert_equal "results/tools/page_speed", Tools::PageSpeed.result_partial
    assert_equal :domain, Tools::PageSpeed.input_type
    assert Tools::PageSpeed.preserve_path_in_input?
    assert_equal({ type: :select, options: %w[mobile desktop] }, Tools::PageSpeed.form_fields[:strategy])
  end

  test "blank URL -> unsuccessful Result, no API call" do
    with_key("tok") do
      res = Tools::PageSpeed.new.execute(domain: "")
      assert_not res.success
      assert_match(/url/i, res.summary)
    end
  end

  test "happy path -> success Result built from the parser, default strategy mobile" do
    with_key(nil) do
      captured = {}
      stub = lambda do |url, strategy:, key:|
        captured.merge!(url: url, strategy: strategy, key: key)
        OK
      end
      PagespeedChecker.stub(:check, stub) do
        res = Tools::PageSpeed.new.execute(domain: "example.com")
        assert res.success
        assert_equal 72, res.data[:scores][:performance]
        assert_equal "https://example.com", captured[:url]   # scheme prepended
        assert_equal "mobile", captured[:strategy]            # default
      end
    end
  end

  test "desktop strategy is passed through" do
    with_key(nil) do
      captured = {}
      PagespeedChecker.stub(:check, ->(_u, strategy:, key:) { captured[:s] = strategy; OK }) do
        Tools::PageSpeed.new.execute(domain: "https://example.com/path", strategy: "desktop")
        assert_equal "desktop", captured[:s]
      end
    end
  end

  test "checker failure -> unsuccessful Result carrying the error" do
    with_key(nil) do
      PagespeedChecker.stub(:check, { success: false, error: "PageSpeed quota exceeded (HTTP 429)" }) do
        res = Tools::PageSpeed.new.execute(domain: "example.com")
        assert_not res.success
        assert_match(/quota/i, res.error)
      end
    end
  end
end
