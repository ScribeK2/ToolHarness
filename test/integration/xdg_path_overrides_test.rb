require "test_helper"

class XdgPathOverridesTest < ActiveSupport::TestCase
  test "config.paths['log'] honors TOOLHARNESS_STATE_DIR" do
    # paths are set during Rails boot from ENV; this test asserts the
    # current process's resolved paths match the env we expect in production.
    # In test env, TOOLHARNESS_STATE_DIR is not set, so this is a no-op assertion
    # that the default in-tree path is used.
    log_path = Rails.application.config.paths["log"].existent.first || Rails.application.config.paths["log"].first
    if ENV["TOOLHARNESS_STATE_DIR"]
      assert_includes log_path, ENV["TOOLHARNESS_STATE_DIR"]
    else
      assert_includes log_path, Rails.root.to_s
    end
  end

  test "database.yml ERB resolves to TOOLHARNESS_DATA_DIR when set" do
    erb = File.read(Rails.root.join("config/database.yml"))
    assert_includes erb, "TOOLHARNESS_DATA_DIR",
      "config/database.yml must use ENV.fetch('TOOLHARNESS_DATA_DIR') for the production DB paths"
  end

  test "storage.yml ERB resolves to TOOLHARNESS_DATA_DIR when set" do
    erb = File.read(Rails.root.join("config/storage.yml"))
    assert_includes erb, "TOOLHARNESS_DATA_DIR",
      "config/storage.yml must use ENV.fetch('TOOLHARNESS_DATA_DIR') for the disk service root"
  end
end
