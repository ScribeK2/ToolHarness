require "test_helper"
require "tmpdir"
require "tool_harness/credential_store"

class ToolHarness::CredentialStoreTest < ActiveSupport::TestCase
  CS = ToolHarness::CredentialStore

  setup do
    @tmp  = Dir.mktmpdir("th-cred-")
    @path = File.join(@tmp, "credentials.yml")
    @store = CS.new(path: @path)
  end

  teardown { FileUtils.remove_entry(@tmp) }

  test "load with missing file returns empty list" do
    assert_equal [], @store.entries
  end

  test "load with malformed YAML returns empty and exposes a parse error" do
    File.write(@path, "this: is: not: valid: [")
    assert_equal [], @store.entries
    assert_match(/yaml/i, @store.last_load_error.to_s)
  end

  test "save + reload an api_key entry; secret_for decrypts, entries omit the secret" do
    @store.save(id: "ipinfo", kind: "api_key", label: "IPinfo", secret: "tok_123")
    fresh = CS.new(path: @path)
    assert_equal "tok_123", fresh.secret_for("ipinfo")
    e = fresh.entry("ipinfo")
    assert_equal "api_key", e[:kind]
    assert_equal "IPinfo", e[:label]
    assert_not e.key?(:secret_enc)
    assert_not fresh.entries.first.key?(:secret_enc)
  end

  test "save a host entry carries host/user; for_kind filters" do
    @store.save(id: "h1", kind: "host", host: "srv.example.com", user: "root", secret: "pw")
    @store.save(id: "ipinfo", kind: "api_key", secret: "tok")
    fresh = CS.new(path: @path)
    hosts = fresh.for_kind("host")
    assert_equal ["h1"], hosts.map { |e| e[:id] }
    assert_equal "srv.example.com", hosts.first[:host]
    assert_equal "root", hosts.first[:user]
  end

  test "delete removes an entry" do
    @store.save(id: "ipinfo", kind: "api_key", secret: "tok")
    @store.delete("ipinfo")
    assert_empty CS.new(path: @path).entries
  end

  test "secret_for is nil for a missing id" do
    assert_nil @store.secret_for("nope")
  end

  test "an undecryptable entry is flagged locked and secret_for returns nil" do
    # Encrypted under a DIFFERENT salt — the store uses CREDENTIALS_SALT, so it can't decrypt.
    bad = ToolHarness::Sql::SecretBox.encrypt("x", salt: "some.other.purpose")
    File.write(@path, YAML.dump([{ "id" => "ipinfo", "kind" => "api_key", "label" => "IPinfo", "secret_enc" => bad }]))
    fresh = CS.new(path: @path)
    assert fresh.entries.first[:locked]
    assert_nil fresh.secret_for("ipinfo")
  end

  test "persist writes the file 0600" do
    @store.save(id: "ipinfo", kind: "api_key", secret: "tok")
    assert_equal 0o600, (File.stat(@path).mode & 0o777)
  end
end
