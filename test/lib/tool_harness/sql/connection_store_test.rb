require "test_helper"
require "tmpdir"
require "tool_harness/sql/connection_store"

class ToolHarness::Sql::ConnectionStoreTest < ActiveSupport::TestCase
  CS = ToolHarness::Sql::ConnectionStore

  setup do
    @tmp  = Dir.mktmpdir("th-sql-")
    @path = File.join(@tmp, "connections.yml")
    @store = CS.new(path: @path)
  end

  teardown { FileUtils.remove_entry(@tmp) }

  test "load with missing file returns empty list" do
    assert_equal [], @store.profiles
  end

  test "load with malformed YAML returns empty list and exposes a parse error" do
    File.write(@path, "this: is: not: valid: yaml: [")
    assert_equal [], @store.profiles
    assert_match(/yaml/i, @store.last_load_error.to_s)
  end

  test "save persists a profile and reload returns it" do
    @store.save(name: "prod", host: "10.1.2.3", port: 4000, user: "ro", password: "secret",
                default_database: "ops", default_mode: "ro", tls_mode: "prefer")

    fresh = CS.new(path: @path)
    p = fresh.profiles.first
    assert_equal "prod",    p[:name]
    assert_equal "10.1.2.3", p[:host]
    assert_equal 4000,       p[:port]
    assert_equal "ops",      p[:default_database]
    assert_equal "ro",       p[:default_mode]
    assert_equal "prefer",   p[:tls_mode]
    assert_equal "secret",   fresh.password_for("prod")
  end

  test "delete removes a profile" do
    @store.save(name: "prod", host: "10.1.2.3", port: 4000, user: "ro", password: "secret",
                default_database: "ops", default_mode: "ro", tls_mode: "prefer")
    @store.delete("prod")
    assert_equal [], CS.new(path: @path).profiles
  end

  test "decryption failure marks profile [locked]" do
    @store.save(name: "prod", host: "10.1.2.3", port: 4000, user: "ro", password: "secret",
                default_database: "ops", default_mode: "ro", tls_mode: "prefer")
    # Swap the on-disk encrypted password to one encrypted with a different key.
    data = YAML.safe_load(File.read(@path), permitted_classes: [Time, Symbol])
    data.first["password_enc"] = ToolHarness::Sql::SecretBox.encrypt("x", key: "z" * 64)
    File.write(@path, YAML.dump(data))

    fresh = CS.new(path: @path)
    assert fresh.profiles.first[:locked]
    assert_nil fresh.password_for("prod")
  end
end
