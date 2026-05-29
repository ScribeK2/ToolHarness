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
end
