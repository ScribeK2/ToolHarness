require "test_helper"

# Proves check() surfaces a whois_text key built by Rdap::WhoisFormatter.
# HTTP + bootstrap are stubbed so no network is touched.
class RdapCheckerWhoisTextTest < ActiveSupport::TestCase
  def no_base_bootstrap
    b = Object.new
    def b.base_for(*) = nil
    b
  end

  test "domain check surfaces whois_text" do
    checker = RdapChecker.new("example.com", bootstrap: no_base_bootstrap)
    def checker.http_get_json(*)
      { status: 200, body: { "ldhName" => "example.com", "entities" => [] } }
    end
    result = checker.check
    assert result[:whois_text].present?, "expected whois_text on domain result"
    assert_match(/^Domain Name: example\.com$/, result[:whois_text])
  end

  test "ip check surfaces whois_text" do
    checker = RdapChecker.new("8.8.8.8", bootstrap: no_base_bootstrap)
    def checker.http_get_json(*)
      { status: 200, body: { "name" => "GOGL", "startAddress" => "8.8.8.0",
                             "endAddress" => "8.8.8.255", "entities" => [] } }
    end
    result = checker.check
    assert result[:whois_text].present?, "expected whois_text on ip result"
    assert_match(/^NetName: GOGL$/, result[:whois_text])
  end
end
