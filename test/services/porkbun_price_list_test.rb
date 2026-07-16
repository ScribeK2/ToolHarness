require "test_helper"

class PorkbunPriceListTest < ActiveSupport::TestCase
  setup { Rails.cache.clear }

  PRICING = {
    "com" => { "registration" => "9.68", "renewal" => "10.37", "transfer" => "9.68" },
    "co.uk" => { "registration" => "6.99", "renewal" => "6.99", "transfer" => "0.00" }
  }.freeze

  # The test env uses :null_store (writes/reads are no-ops), so swap in a real
  # in-memory store for the duration of any test that exercises caching.
  def with_memory_cache
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = original
  end

  test "resolves a simple TLD to its registration/renewal/transfer prices" do
    list = PorkbunPriceList.new
    list.stub(:fetch, PRICING) do
      price = list.price_for("example.com")
      assert_equal "com", price[:tld]
      assert_equal 9.68, price[:registration]
      assert_equal 10.37, price[:renewal]
      assert_equal 9.68, price[:transfer]
    end
  end

  test "resolves compound TLDs via longest-suffix match" do
    list = PorkbunPriceList.new
    list.stub(:fetch, PRICING) do
      price = list.price_for("example.co.uk")
      assert_equal "co.uk", price[:tld]
      assert_equal 0.0, price[:transfer]
    end
  end

  test "returns nil for a TLD not in the price list" do
    list = PorkbunPriceList.new
    list.stub(:fetch, PRICING) do
      assert_nil list.price_for("example.zzz")
    end
  end

  test "caches a successful fetch so a second instance does not refetch" do
    with_memory_cache do
      calls = 0
      fetcher = ->(*) { calls += 1; PRICING }
      list = PorkbunPriceList.new
      list.stub(:fetch, fetcher) do
        list.price_for("example.com")
      end

      list2 = PorkbunPriceList.new
      list2.stub(:fetch, ->(*) { flunk "should have hit the cache, not fetched again" }) do
        price = list2.price_for("example.com")
        assert_equal 9.68, price[:registration]
      end
      assert_equal 1, calls, "expected fetch called once then cached"
    end
  end

  test "does not cache a failed fetch, so it is retried on the next call" do
    with_memory_cache do
      list = PorkbunPriceList.new
      list.stub(:fetch, nil) { assert_nil list.price_for("example.com") }

      list2 = PorkbunPriceList.new
      list2.stub(:fetch, PRICING) do
        assert_equal 9.68, list2.price_for("example.com")[:registration]
      end
    end
  end

  test "self.price_for is a convenience class method" do
    instance = PorkbunPriceList.new
    instance.stub(:fetch, PRICING) do
      PorkbunPriceList.stub(:new, instance) do
        price = PorkbunPriceList.price_for("example.com")
        assert_equal 9.68, price[:registration]
      end
    end
  end
end
