require "test_helper"

class ToolHarness::HistoricalDns::ProviderTest < ActiveSupport::TestCase
  # A fake store responding to #secret_for, like ToolHarness::CredentialStore.
  Store = Struct.new(:secrets) do
    def secret_for(id) = secrets[id.to_s]
  end

  class Keyed < ToolHarness::HistoricalDns::Provider
    def self.id = "keyed"
    def self.display_name = "Keyed"
    def self.requires_key? = true
  end

  class Free < ToolHarness::HistoricalDns::Provider
    def self.id = "free"
    def self.display_name = "Free"
    def self.requires_key? = false
  end

  test "free provider is always available" do
    assert Free.new.available?(Store.new({}))
  end

  test "keyed provider availability depends on a present secret" do
    assert_not Keyed.new.available?(Store.new({}))
    assert     Keyed.new.available?(Store.new({ "keyed" => "tok" }))
  end

  test "raise_for_status maps HTTP codes to ProviderError categories" do
    p = Free.new
    err = assert_raises(ToolHarness::HistoricalDns::ProviderError) { p.send(:raise_for_status, 401, nil) }
    assert_equal :bad_key, err.category
    assert_equal :rate_limited, assert_raises(ToolHarness::HistoricalDns::ProviderError) { p.send(:raise_for_status, 429, nil) }.category
    assert_equal :unavailable, assert_raises(ToolHarness::HistoricalDns::ProviderError) { p.send(:raise_for_status, 0, "boom") }.category
    assert_equal :unavailable, assert_raises(ToolHarness::HistoricalDns::ProviderError) { p.send(:raise_for_status, 500, nil) }.category
  end

  test ".all lists every registered provider" do
    ids = ToolHarness::HistoricalDns::Provider.all.map(&:id)
    assert_equal %w[crtsh livedns mnemonic virustotal whoisfreaks].sort, ids.sort
  end

  test "timeouts default to 3/9 and crt.sh overrides read (it's known-slow)" do
    assert_equal 3,  ToolHarness::HistoricalDns::Virustotal.open_timeout
    assert_equal 9,  ToolHarness::HistoricalDns::Virustotal.read_timeout
    assert_equal 12, ToolHarness::HistoricalDns::Crtsh.read_timeout
  end
end
