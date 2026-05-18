require "test_helper"
require "minitest/mock"
require "net/http"

class UpdateCheckerTest < ActiveSupport::TestCase
  setup do
    # The test env default cache_store is :null_store. Swap to MemoryStore so
    # cache reads/writes behave normally for these tests.
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    Rails.cache = @original_cache
  end

  test "current_version reads from VERSION file" do
    assert_equal File.read(Rails.root.join("VERSION")).strip, UpdateChecker.current_version
  end

  test "banner_data returns nil when cache is empty" do
    assert_nil UpdateChecker.banner_data
  end

  test "banner_data returns nil when latest equals current" do
    Rails.cache.write(UpdateChecker::CACHE_KEY, {
      "tag_name" => "v#{UpdateChecker.current_version}",
      "html_url" => "https://example.com/x"
    }, expires_in: 24.hours)
    assert_nil UpdateChecker.banner_data
  end

  test "banner_data returns hash when latest is newer than current" do
    Rails.cache.write(UpdateChecker::CACHE_KEY, {
      "tag_name"     => "v99.0.0",
      "html_url"     => "https://github.com/ScribeK2/ToolHarness/releases/tag/v99.0.0",
      "appimage_url" => "https://example.com/TH.AppImage"
    }, expires_in: 24.hours)
    data = UpdateChecker.banner_data
    assert_equal "99.0.0", data[:version]
    assert_equal "https://github.com/ScribeK2/ToolHarness/releases/tag/v99.0.0", data[:url]
    assert_equal "https://example.com/TH.AppImage", data[:appimage_url]
    assert_equal true, data[:available]
  end

  test "refresh! silently swallows network errors" do
    Net::HTTP.stub(:start, ->(*_a, **_k, &_b) { raise SocketError, "no dns" }) do
      assert_nothing_raised { UpdateChecker.refresh! }
    end
    assert_nil Rails.cache.read(UpdateChecker::CACHE_KEY)
  end

  test "refresh! caches appimage_url from the first .AppImage asset" do
    response_body = {
      "tag_name" => "v99.0.0",
      "html_url" => "https://github.com/ScribeK2/ToolHarness/releases/tag/v99.0.0",
      "assets" => [
        { "name" => "SHA256SUMS",                         "browser_download_url" => "https://example.com/SHA256SUMS" },
        { "name" => "ToolHarness-99.0.0-x86_64.AppImage", "browser_download_url" => "https://example.com/TH.AppImage" }
      ]
    }.to_json

    fake_resp = Net::HTTPSuccess.allocate
    fake_resp.define_singleton_method(:body) { response_body }

    fake_http = Object.new
    fake_http.define_singleton_method(:request) { |_req| fake_resp }

    Net::HTTP.stub(:start, ->(*_a, **_k, &blk) { blk.call(fake_http) }) do
      UpdateChecker.refresh!
    end

    cached = Rails.cache.read(UpdateChecker::CACHE_KEY)
    assert_equal "v99.0.0",                         cached["tag_name"]
    assert_equal "https://example.com/TH.AppImage", cached["appimage_url"]
  end

  test "refresh! caches nil appimage_url when no .AppImage asset is present" do
    response_body = {
      "tag_name" => "v99.0.0",
      "html_url" => "https://github.com/ScribeK2/ToolHarness/releases/tag/v99.0.0",
      "assets" => [
        { "name" => "SHA256SUMS", "browser_download_url" => "https://example.com/SHA256SUMS" }
      ]
    }.to_json

    fake_resp = Net::HTTPSuccess.allocate
    fake_resp.define_singleton_method(:body) { response_body }

    fake_http = Object.new
    fake_http.define_singleton_method(:request) { |_req| fake_resp }

    Net::HTTP.stub(:start, ->(*_a, **_k, &blk) { blk.call(fake_http) }) do
      UpdateChecker.refresh!
    end

    cached = Rails.cache.read(UpdateChecker::CACHE_KEY)
    assert_nil cached["appimage_url"]
  end
end
