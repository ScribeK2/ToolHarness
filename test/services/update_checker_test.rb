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
      "tag_name" => "v99.0.0",
      "html_url" => "https://github.com/ScribeK2/ToolHarness/releases/tag/v99.0.0"
    }, expires_in: 24.hours)
    data = UpdateChecker.banner_data
    assert_equal "99.0.0", data[:version]
    assert_equal "https://github.com/ScribeK2/ToolHarness/releases/tag/v99.0.0", data[:url]
    assert_equal true, data[:available]
  end

  test "refresh! silently swallows network errors" do
    Net::HTTP.stub(:start, ->(*_a, **_k, &_b) { raise SocketError, "no dns" }) do
      assert_nothing_raised { UpdateChecker.refresh! }
    end
    assert_nil Rails.cache.read(UpdateChecker::CACHE_KEY)
  end
end
