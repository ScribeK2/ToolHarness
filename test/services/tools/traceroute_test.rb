require "test_helper"

class TracerouteRegistrationTest < ActiveSupport::TestCase
  test "traceroute is NOT registered by default in v1 AppImage builds" do
    # AppImages can't carry CAP_NET_RAW; traceroute is feature-flagged off
    # until we have a pure-userspace replacement. Spec: section 4.
    refute ENV["TOOLHARNESS_TRACEROUTE_ENABLED"] == "1",
      "Test env should not have the flag set — unset it before running."
    refute ToolHarness::Registry.tools.key?(:traceroute),
      "Traceroute must not be registered when TOOLHARNESS_TRACEROUTE_ENABLED is unset"
  end
end
