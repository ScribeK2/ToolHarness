require "test_helper"
require "tool_harness/command_dispatcher"

class ToolHarness::CommandDispatcherTest < ActiveSupport::TestCase
  test "parses :run tool target into a structured action" do
    cmd = ToolHarness::CommandDispatcher.parse(":run whois example.com")
    assert_equal :run, cmd.name
    assert_equal({ tool: "whois", target: "example.com" }, cmd.args)
  end

  test "parses :export json" do
    cmd = ToolHarness::CommandDispatcher.parse(":export json")
    assert_equal :export, cmd.name
    assert_equal({ format: "json" }, cmd.args)
  end

  test "parses :purge older=90d" do
    cmd = ToolHarness::CommandDispatcher.parse(":purge older=90d")
    assert_equal :purge, cmd.name
    assert_equal({ older: "90d" }, cmd.args)
  end

  test "leading colon is optional" do
    cmd = ToolHarness::CommandDispatcher.parse("run whois example.com")
    assert_equal :run, cmd.name
  end

  test "unknown command returns :unknown" do
    cmd = ToolHarness::CommandDispatcher.parse(":nope")
    assert_equal :unknown, cmd.name
    assert_equal({ raw: "nope" }, cmd.args)
  end

  test "empty input returns :empty" do
    cmd = ToolHarness::CommandDispatcher.parse("")
    assert_equal :empty, cmd.name
  end

  test ":investigate parses the domain arg" do
    cmd = ToolHarness::CommandDispatcher.parse(":investigate example.com")
    assert_equal :investigate, cmd.name
    assert_equal "example.com", cmd.args[:domain]
  end

  test "investigate parses an optional track argument" do
    cmd = ToolHarness::CommandDispatcher.parse(":investigate example.com email_delivery")
    assert_equal :investigate, cmd.name
    assert_equal "example.com", cmd.args[:domain]
    assert_equal "email_delivery", cmd.args[:track]
  end

  test "investigate without a track omits the key" do
    cmd = ToolHarness::CommandDispatcher.parse(":investigate example.com")
    assert_equal "example.com", cmd.args[:domain]
    assert_nil cmd.args[:track]
  end
end
