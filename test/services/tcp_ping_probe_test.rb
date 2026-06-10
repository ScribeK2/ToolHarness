require "test_helper"

class TcpPingProbeTest < ActiveSupport::TestCase
  test "does not shell out to system ping" do
    src = File.read(Rails.root.join("app/services/tcp_ping_probe.rb"))
    refute_match(/Open3/, src, "TcpPingProbe must not use Open3")
    refute_match(/`[^`]*ping[^`]*`/, src, "TcpPingProbe must not backtick-shell to ping")
    refute_match(/\bsystem\(["']ping/, src, "TcpPingProbe must not call system('ping', ...)")
  end

  test "rejects invalid input" do
    result = TcpPingProbe.check("not a host!")
    assert_equal false, result[:valid]
  end

  test "reports unreachable for guaranteed-closed RFC5737 address" do
    # 192.0.2.0/24 is reserved for documentation; nothing answers there.
    # Keep PACKET_COUNT small via constant override for fast tests.
    stub_const(TcpPingProbe, :PACKET_COUNT, 2) do
      stub_const(TcpPingProbe, :PACKET_TIMEOUT_S, 1) do
        result = TcpPingProbe.check("192.0.2.1")
        refute result[:reachable]
        assert_equal 0, result[:data][:received]
        assert_equal 2, result[:data][:sent]
      end
    end
  end

  private

  # Minimal const-stubbing helper since we don't depend on Mocha.
  def stub_const(klass, const, value)
    original = klass.const_get(const)
    klass.send(:remove_const, const)
    klass.const_set(const, value)
    yield
  ensure
    klass.send(:remove_const, const)
    klass.const_set(const, original)
  end
end
