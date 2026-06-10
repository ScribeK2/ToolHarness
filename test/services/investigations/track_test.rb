require "test_helper"

class Investigations::TrackTest < ActiveSupport::TestCase
  test "orientation track has the three probes and a correlator" do
    t = Investigations::Track.find("orientation")
    assert_equal "orientation", t.key
    assert_equal "Orientation", t.label
    assert_equal %w[whois_lookup dns_lookup hosting_diagnostic], t.probes
    assert_equal Investigations::OrientationCorrelator, t.correlator
  end

  test "find raises for an unknown track" do
    assert_raises(KeyError) { Investigations::Track.find("nope") }
  end

  test "all returns the registered tracks" do
    assert_includes Investigations::Track.all.map(&:key), "orientation"
  end

  test "email_delivery track has the four probes and the EmailDeliveryCorrelator" do
    t = Investigations::Track.find("email_delivery")
    assert_equal "email_delivery", t.key
    assert_equal "Email Delivery", t.label
    assert_equal %w[dns_lookup email_auth_check hosting_diagnostic blacklist], t.probes
    assert_equal Investigations::EmailDeliveryCorrelator, t.correlator
  end

  test "blacklist is declared dependent on dns_lookup" do
    spec = Investigations::Track.find("email_delivery").specs.find { |s| s.tool_key == "blacklist" }
    assert_equal "dns_lookup", spec.depends_on
    assert_equal :primary_mx_host, spec.target
  end

  test "orientation probes are all independent (no depends_on)" do
    assert Investigations::Track.find("orientation").specs.all? { |s| s.depends_on.nil? }
  end

  test "exists? is true for a registered track and false otherwise" do
    assert Investigations::Track.exists?("email_delivery")
    assert_not Investigations::Track.exists?("nope")
  end

  test "hosting_website track has the five probes and the HostingWebsiteCorrelator" do
    t = Investigations::Track.find("hosting_website")
    assert_equal "hosting_website", t.key
    assert_equal "Hosting & Website", t.label
    assert_equal %w[dns_lookup hosting_diagnostic http_inspect ssl_inspect website_health], t.probes
    assert_equal Investigations::HostingWebsiteCorrelator, t.correlator
  end

  test "hosting_website probes are all independent (no depends_on)" do
    assert Investigations::Track.find("hosting_website").specs.all? { |s| s.depends_on.nil? }
  end
end
