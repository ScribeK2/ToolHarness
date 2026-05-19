require "test_helper"
require "tmpdir"
require "tool_harness/sql/connection_store"
require_relative "../../../support/fake_mysql2_client"

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

  setup_pool = lambda do |t|
    FakeMysql2Client.reset!
    ToolHarness::Sql::ConnectionStore.client_factory = ->(opts) { FakeMysql2Client.new(opts) }
  end
  teardown_pool = lambda do |t|
    ToolHarness::Sql::ConnectionStore.client_factory = nil
    ToolHarness::Sql::ConnectionStore.pool = {}
  end

  test "client_for opens a Mysql2::Client with the profile's options" do
    instance_exec(self, &setup_pool)
    @store.save(name: "prod", host: "10.1.2.3", port: 4000, user: "ro", password: "secret",
                default_database: "ops", default_mode: "ro", tls_mode: "prefer")
    @store.client_for("prod")
    fake = FakeMysql2Client.instances.last
    assert_equal "10.1.2.3", fake.init_opts[:host]
    assert_equal 4000,       fake.init_opts[:port]
    assert_equal "ro",       fake.init_opts[:username]
    assert_equal "secret",   fake.init_opts[:password]
    assert_equal "ops",      fake.init_opts[:database]
    assert_equal :preferred, fake.init_opts[:ssl_mode]
    instance_exec(self, &teardown_pool)
  end

  test "client_for caches and returns the same client across calls" do
    instance_exec(self, &setup_pool)
    @store.save(name: "prod", host: "h", port: 4000, user: "u", password: "p",
                default_database: "d", default_mode: "ro", tls_mode: "prefer")
    a = @store.client_for("prod")
    b = @store.client_for("prod")
    assert_same a, b
    assert_equal 1, FakeMysql2Client.instances.size
    instance_exec(self, &teardown_pool)
  end

  test "disconnect closes and forgets the client" do
    instance_exec(self, &setup_pool)
    @store.save(name: "prod", host: "h", port: 4000, user: "u", password: "p",
                default_database: "d", default_mode: "ro", tls_mode: "prefer")
    c = @store.client_for("prod")
    @store.disconnect("prod")
    assert c.closed
    @store.client_for("prod")
    assert_equal 2, FakeMysql2Client.instances.size
    instance_exec(self, &teardown_pool)
  end
end
