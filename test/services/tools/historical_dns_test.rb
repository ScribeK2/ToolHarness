require "test_helper"

class Tools::HistoricalDnsTest < ActiveSupport::TestCase
  HD = ToolHarness::HistoricalDns
  R  = HD::Record

  # Fake credential store: knows which ids have a secret.
  FakeStore = Struct.new(:ids) do
    def secret_for(id) = ids.include?(id.to_s) ? "secret-#{id}" : nil
    def touch!(_id) = nil
  end

  # Build a one-off provider class with canned behaviour.
  def provider_class(id:, requires_key:, behavior:)
    Class.new(HD::Provider) do
      @id = id; @requires_key = requires_key; @behavior = behavior
      class << self
        attr_reader :behavior
        def id = @id
        def display_name = @id.capitalize
        def requires_key? = @requires_key
      end
      define_method(:fetch) { |_domain, key: nil| self.class.behavior.call }
    end
  end

  def run_tool(domain: "example.com", providers:, store_ids: [])
    Rails.cache.clear
    HD::Provider.stub(:all, providers) do
      ToolHarness::CredentialStore.stub(:new, FakeStore.new(store_ids)) do
        Tools::HistoricalDns.new.run(domain: domain)
      end
    end
  end

  test "no keys: only crt.sh runs, success with subdomains + providers_limited info" do
    crt = provider_class(id: "crtsh", requires_key: false,
            behavior: -> { { records: [], subdomains: [{ name: "mail.example.com", first_seen: Date.new(2023, 1, 1), last_seen: Date.new(2026, 5, 1) }] } })
    wf  = provider_class(id: "whoisfreaks", requires_key: true, behavior: -> { raise "should not run" })
    vt  = provider_class(id: "virustotal",  requires_key: true, behavior: -> { raise "should not run" })

    res = run_tool(providers: [crt, wf, vt], store_ids: [])
    assert res.success?
    assert_equal 1, res.data[:subdomains].size
    assert(res.issues.any? { |i| i["code"] == "providers_limited" })
    statuses = res.data[:providers].to_h { |p| [p[:id], p[:status]] }
    assert_equal "no_key", statuses["whoisfreaks"]
    assert_equal "ok",     statuses["crtsh"]
  end

  test "partial failure: one provider errors, others' data still returned with a warning" do
    crt = provider_class(id: "crtsh", requires_key: false, behavior: -> { { records: [], subdomains: [] } })
    wf  = provider_class(id: "whoisfreaks", requires_key: true,
            behavior: -> { { records: [R.new(type: :ns, value: "ns1.cloudflare.com", first_seen: Date.new(2024, 3, 1), last_seen: Date.new(2026, 6, 1), sources: ["whoisfreaks"])], subdomains: [] } })
    vt  = provider_class(id: "virustotal", requires_key: true,
            behavior: -> { raise HD::ProviderError.new(:rate_limited, "VirusTotal rate limit reached (HTTP 429)") })

    res = run_tool(providers: [crt, wf, vt], store_ids: %w[whoisfreaks virustotal])
    assert res.success?
    assert_equal ["ns1.cloudflare.com"], res.data[:timeline]["ns"].map { |m| m[:value] }
    assert(res.issues.any? { |i| i["code"] == "provider_failed" && i["message"].match?(/rate limit/i) })
  end

  test "all available providers fail: success false with aggregated error" do
    crt = provider_class(id: "crtsh", requires_key: false, behavior: -> { raise HD::ProviderError.new(:unavailable, "crt.sh down") })
    res = run_tool(providers: [crt], store_ids: [])
    assert_not res.success?
    assert_match(/crt\.sh down/, res.error)
  end

  test "clean result is cached; degraded (error) result is not" do
    # Test env uses :null_store (writes discarded), so run under a real MemoryStore.
    Rails.stub(:cache, ActiveSupport::Cache::MemoryStore.new) do
      good = provider_class(id: "crtsh", requires_key: false,
               behavior: -> { { records: [], subdomains: [{ name: "a.example.com", first_seen: Date.new(2023, 1, 1), last_seen: Date.new(2026, 1, 1) }] } })
      run_tool(providers: [good], store_ids: [])
      assert Rails.cache.read("toolharness:historical_dns:example.com"), "clean result should be cached"

      bad = provider_class(id: "crtsh", requires_key: false,
              behavior: -> { raise HD::ProviderError.new(:unavailable, "boom") })
      # different domain to avoid the cache write above
      HD::Provider.stub(:all, [bad]) do
        ToolHarness::CredentialStore.stub(:new, FakeStore.new([])) do
          Tools::HistoricalDns.new.run(domain: "nope.com")
        end
      end
      assert_nil Rails.cache.read("toolharness:historical_dns:nope.com"), "degraded result must not be cached"
    end
  end

  test "blank domain fails cleanly without raising" do
    res = nil
    assert_nothing_raised { res = Tools::HistoricalDns.new.run(domain: "") }
    assert_not res.success?
  end

  private

  def assert_nothing_raised
    yield
  rescue => e
    flunk "expected no exception, got #{e.class}: #{e.message}"
  end
end
