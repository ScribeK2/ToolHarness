require "test_helper"
require "tool_harness/sql/secret_box"

class ToolHarness::Sql::SecretBoxTest < ActiveSupport::TestCase
  SB = ToolHarness::Sql::SecretBox

  test "encrypt → decrypt roundtrips a string" do
    cipher = SB.encrypt("p4ssw0rd!", key: "k" * 64)
    refute_equal "p4ssw0rd!", cipher
    assert_equal "p4ssw0rd!", SB.decrypt(cipher, key: "k" * 64)
  end

  test "decrypt with a different key raises a DecryptError" do
    cipher = SB.encrypt("p4ssw0rd!", key: "k" * 64)
    assert_raises(SB::DecryptError) { SB.decrypt(cipher, key: "x" * 64) }
  end

  test "decrypt of garbage raises a DecryptError" do
    assert_raises(SB::DecryptError) { SB.decrypt("not-a-cipher", key: "k" * 64) }
  end

  test "default key is taken from Rails.application.secret_key_base" do
    cipher = SB.encrypt("foo")
    assert_equal "foo", SB.decrypt(cipher)
  end

  test "a salt produces a key-separated ciphertext: same salt roundtrips" do
    cipher = SB.encrypt("p4ss", key: "k" * 64, salt: "purpose.a")
    assert_equal "p4ss", SB.decrypt(cipher, key: "k" * 64, salt: "purpose.a")
  end

  test "decrypt with a different salt raises a DecryptError" do
    cipher = SB.encrypt("p4ss", key: "k" * 64, salt: "purpose.a")
    assert_raises(SB::DecryptError) { SB.decrypt(cipher, key: "k" * 64, salt: "purpose.b") }
  end

  test "default salt path is unchanged (no salt arg)" do
    cipher = SB.encrypt("p4ss", key: "k" * 64)
    assert_equal "p4ss", SB.decrypt(cipher, key: "k" * 64)
  end
end
