require "test_helper"
require "tmpdir"

class Credentials::EntriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @tmp  = Dir.mktmpdir("th-cred-")
    @prev = ENV["TOOLHARNESS_CONFIG_DIR"]
    ENV["TOOLHARNESS_CONFIG_DIR"] = @tmp
  end

  teardown do
    ENV["TOOLHARNESS_CONFIG_DIR"] = @prev
    FileUtils.remove_entry(@tmp)
  end

  test "create stores an api_key entry" do
    post credentials_entries_path, params: { id: "ipinfo", kind: "api_key", label: "IPinfo", secret: "tok_secret_123" }
    assert_response :success
    store = ToolHarness::CredentialStore.new
    assert_equal "tok_secret_123", store.secret_for("ipinfo")
    assert_equal "api_key", store.entry("ipinfo")[:kind]
  end

  test "create stores a host entry with host and user" do
    post credentials_entries_path, params: { id: "h1", kind: "host", host: "srv.example.com", user: "root", secret: "pw" }
    e = ToolHarness::CredentialStore.new.entry("h1")
    assert_equal "srv.example.com", e[:host]
    assert_equal "root", e[:user]
  end

  test "invalid id is rejected and nothing is persisted" do
    post credentials_entries_path, params: { id: "Bad ID!", kind: "api_key", secret: "x" }
    assert_response :success
    assert_empty ToolHarness::CredentialStore.new.entries
  end

  test "destroy removes an entry" do
    ToolHarness::CredentialStore.new.save(id: "ipinfo", kind: "api_key", secret: "x")
    delete credentials_entry_path("ipinfo")
    assert_empty ToolHarness::CredentialStore.new.entries
  end

  test "the credentials pane lists entries but never the secret, and has a masked field" do
    ToolHarness::CredentialStore.new.save(id: "ipinfo", kind: "api_key", label: "IPinfo", secret: "tok_secret_123")
    get workbench_path(tool: "credentials")
    assert_response :success
    assert_match("ipinfo", response.body)
    assert_no_match(/tok_secret_123/, response.body)
    assert_match(/type="password"/, response.body)
  end
end
