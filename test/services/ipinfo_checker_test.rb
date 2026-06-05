require "test_helper"

class IpinfoCheckerTest < ActiveSupport::TestCase
  def check_with(status:, body:, error: nil)
    c = IpinfoChecker.new("1.2.3.4", token: "tok")
    c.stub(:http_get_json, ->(_url) { { status: status, body: body, error: error } }) { c.check }
  end

  PAID = {
    "ip" => "1.2.3.4", "hostname" => "host.example", "city" => "Mountain View",
    "region" => "California", "country" => "US", "loc" => "37.4,-122.0",
    "postal" => "94043", "timezone" => "America/Los_Angeles",
    "asn" => { "asn" => "AS15169", "name" => "Google LLC" },
    "company" => { "name" => "Google", "domain" => "google.com", "type" => "hosting" },
    "privacy" => { "vpn" => false, "proxy" => false, "tor" => false, "relay" => false, "hosting" => true }
  }.freeze

  test "paid response maps geo, asn object, company, privacy" do
    r = check_with(status: 200, body: PAID)
    assert r[:success]
    assert_equal "Mountain View", r[:city]
    assert_equal({ id: "AS15169", name: "Google LLC" }, r[:asn])
    assert_equal "google.com", r[:company][:domain]
    assert_equal true, r[:privacy][:hosting]
    assert_nil r[:org] # raw org dropped when asn parsed
  end

  test "free-tier response parses asn from org string; no privacy/company" do
    r = check_with(status: 200, body: { "ip" => "1.2.3.4", "city" => "Reno", "country" => "US", "org" => "AS7922 Comcast" })
    assert r[:success]
    assert_equal({ id: "AS7922", name: "Comcast" }, r[:asn])
    assert_nil r[:privacy]
    assert_nil r[:company]
  end

  test "unparseable org is kept as a raw org field" do
    r = check_with(status: 200, body: { "ip" => "1.2.3.4", "org" => "SomeISP Networks" })
    assert_nil r[:asn]
    assert_equal "SomeISP Networks", r[:org]
  end

  test "401 -> invalid key error" do
    r = check_with(status: 401, body: nil)
    assert_not r[:success]
    assert_match(/rejected the API key/i, r[:error])
  end

  test "429 -> rate limit error" do
    r = check_with(status: 429, body: nil)
    assert_match(/rate limit/i, r[:error])
  end

  test "network failure (status 0) -> error" do
    r = check_with(status: 0, body: nil, error: "timeout")
    assert_not r[:success]
    assert_match(/timeout/, r[:error])
  end
end
