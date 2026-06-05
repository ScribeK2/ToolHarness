require "test_helper"

class Tools::IpinfoTest < ActiveSupport::TestCase
  RAW = { success: true, ip: "1.2.3.4", hostname: "h.example", city: "Reno", region: "NV",
          country: "US", loc: "39,-119", postal: "89501", timezone: "America/Los_Angeles",
          asn: { id: "AS7922", name: "Comcast" }, org: nil, company: nil,
          privacy: { vpn: false, proxy: false, tor: false, relay: false, hosting: true } }.freeze

  # Stub CredentialStore.new to return an object whose #secret_for yields `token`.
  def with_key(token, &blk)
    fake = Object.new
    fake.define_singleton_method(:secret_for) { |_id| token }
    ToolHarness::CredentialStore.stub(:new, fake, &blk)
  end

  test "no key -> unsuccessful Result pointing at the Credentials tool" do
    with_key(nil) do
      res = Tools::Ipinfo.new.execute(domain: "1.2.3.4")
      assert_not res.success
      assert_match(/Credentials tool/i, res.summary)
    end
  end

  test "IP input -> direct lookup, no resolved_from" do
    with_key("tok") do
      IpinfoChecker.stub(:check, RAW) do
        res = Tools::Ipinfo.new.execute(domain: "1.2.3.4")
        assert res.success
        assert_equal "1.2.3.4", res.data[:ip]
        assert_not res.data.key?(:resolved_from)
        assert_equal({ id: "AS7922", name: "Comcast" }, res.data[:asn])
      end
    end
  end

  test "hostname -> resolves to A record and records resolved_from" do
    with_key("tok") do
      DnsChecker.stub(:check, { a_records: ["1.2.3.4"] }) do
        IpinfoChecker.stub(:check, RAW) do
          res = Tools::Ipinfo.new.execute(domain: "example.com")
          assert res.success
          assert_equal "example.com", res.data[:resolved_from]
        end
      end
    end
  end

  test "unresolvable hostname -> unsuccessful Result" do
    with_key("tok") do
      DnsChecker.stub(:check, { a_records: [] }) do
        res = Tools::Ipinfo.new.execute(domain: "nope.example")
        assert_not res.success
        assert_match(/could not resolve/i, res.error)
      end
    end
  end

  test "privacy flag set -> info privacy_flagged issue" do
    with_key("tok") do
      IpinfoChecker.stub(:check, RAW) do
        res = Tools::Ipinfo.new.execute(domain: "1.2.3.4")
        issue = res.issues.find { |i| i["code"] == "privacy_flagged" }
        assert issue
        assert_match(/hosting/, issue["message"])
      end
    end
  end

  test "checker error -> unsuccessful Result" do
    with_key("tok") do
      IpinfoChecker.stub(:check, { success: false, error: "IPinfo rate limit reached (HTTP 429)" }) do
        res = Tools::Ipinfo.new.execute(domain: "1.2.3.4")
        assert_not res.success
        assert_match(/rate limit/i, res.error)
      end
    end
  end
end
