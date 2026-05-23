require "test_helper"
require "tool_harness/command_dispatcher"

class CommandDispatcherSqlTest < ActiveSupport::TestCase
  CD = ToolHarness::CommandDispatcher

  test ":c with profile name" do
    cmd = CD.parse(":c prod-ops")
    assert_equal :c, cmd.name
    assert_equal({}, cmd.args)
  end

  test ":c host=10.x port=4000 user=foo" do
    cmd = CD.parse(":c host=10.x port=4000 user=foo")
    assert_equal :c, cmd.name
    assert_equal({ host: "10.x", port: "4000", user: "foo" }, cmd.args)
  end

  test ":w on" do
    cmd = CD.parse(":w on")
    assert_equal :w, cmd.name
    assert_equal({ mode: "on" }, cmd.args)
  end

  test ":db ops_main" do
    cmd = CD.parse(":db ops_main")
    assert_equal({ name: "ops_main" }, cmd.args)
  end

  test ":h 3" do
    cmd = CD.parse(":h 3")
    assert_equal({ index: 3 }, cmd.args)
  end

  test ":limit 1000" do
    cmd = CD.parse(":limit 1000")
    assert_equal({ n: 1000 }, cmd.args)
  end
end
