require "test_helper"
require "tmpdir"

class PorkbunPriceListTest < ActiveSupport::TestCase
  SNAPSHOT = {
    "fetched_at" => "2026-07-16",
    "pricing" => {
      "com" => { "registration" => "9.68", "renewal" => "10.37", "transfer" => "9.68" },
      "co.uk" => { "registration" => "6.99", "renewal" => "6.99", "transfer" => "0.00" }
    }
  }.freeze

  def with_snapshot(content)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "porkbun_pricing.json")
      File.write(path, content) unless content.nil?
      yield PorkbunPriceList.new(path: path)
    end
  end

  test "resolves a simple TLD to its registration/renewal/transfer prices" do
    with_snapshot(JSON.generate(SNAPSHOT)) do |list|
      price = list.price_for("example.com")
      assert_equal "com", price[:tld]
      assert_equal 9.68, price[:registration]
      assert_equal 10.37, price[:renewal]
      assert_equal 9.68, price[:transfer]
    end
  end

  test "resolves compound TLDs via longest-suffix match" do
    with_snapshot(JSON.generate(SNAPSHOT)) do |list|
      price = list.price_for("example.co.uk")
      assert_equal "co.uk", price[:tld]
      assert_equal 0.0, price[:transfer]
    end
  end

  test "returns nil for a TLD not in the price list" do
    with_snapshot(JSON.generate(SNAPSHOT)) do |list|
      assert_nil list.price_for("example.zzz")
    end
  end

  test "carries the snapshot date through on every price" do
    with_snapshot(JSON.generate(SNAPSHOT)) do |list|
      assert_equal "2026-07-16", list.price_for("example.com")[:as_of]
      assert_equal "2026-07-16", list.snapshot_date
    end
  end

  test "returns nil without raising when the snapshot file is missing" do
    with_snapshot(nil) do |list|
      assert_nil list.price_for("example.com")
      assert_nil list.snapshot_date
    end
  end

  test "returns nil without raising when the snapshot file is malformed" do
    with_snapshot("not json {{{") do |list|
      assert_nil list.price_for("example.com")
    end
  end

  test "self.price_for reads the bundled snapshot path" do
    # The class method uses the default PATH (the committed snapshot). It must
    # not raise even if the file is absent in a fresh checkout.
    assert_nothing_raised { PorkbunPriceList.price_for("example.com") }
  end
end
