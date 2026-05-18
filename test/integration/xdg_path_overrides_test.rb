require "test_helper"
require "tmpdir"

class XdgPathOverridesTest < ActiveSupport::TestCase
  test "config.paths['log'] defaults to in-tree when TOOLHARNESS_STATE_DIR is unset" do
    log_path = Rails.application.config.paths["log"].existent.first || Rails.application.config.paths["log"].first
    assert_includes log_path, Rails.root.to_s
  end

  test "config.paths['log'] redirects under TOOLHARNESS_STATE_DIR in a fresh Rails process" do
    Dir.mktmpdir do |dir|
      cmd = %(TOOLHARNESS_STATE_DIR=#{dir} bin/rails runner 'puts Rails.application.config.paths["log"].to_a.first' 2>&1)
      out = `#{cmd}`
      assert_match Regexp.new(Regexp.escape(dir)), out,
        "log path should be redirected under #{dir}; got: #{out.inspect}"
    end
  end

  test "config.paths['tmp'] redirects under TOOLHARNESS_STATE_DIR in a fresh Rails process" do
    Dir.mktmpdir do |dir|
      cmd = %(TOOLHARNESS_STATE_DIR=#{dir} bin/rails runner 'puts Rails.application.config.paths["tmp"].to_a.first' 2>&1)
      out = `#{cmd}`
      assert_match Regexp.new(Regexp.escape(dir)), out,
        "tmp path should be redirected under #{dir}; got: #{out.inspect}"
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
