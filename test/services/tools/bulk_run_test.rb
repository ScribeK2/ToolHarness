require "test_helper"

class Tools::BulkRunTest < ActiveSupport::TestCase
  test "execute raises NotImplementedError (managed via BatchesController)" do
    assert_raises(NotImplementedError) { Tools::BulkRun.new.execute(domains: "a.com", tool_key: "dns_lookup") }
  end

  test "declares the batches/form custom partial" do
    assert_equal "batches/form", Tools::BulkRun.custom_partial
  end
end
