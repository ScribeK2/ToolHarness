require "test_helper"

class EmailHeaderParserTest < ActiveSupport::TestCase
  test "normalizes folded headers, strips forward quote markers, cuts at blank line" do
    raw = <<~RAW
      > From: Alice <alice@ex.com>
      > Subject: multi
      >  line subject
      > X-Body-Should-Be: ignored

      This is the body and must be ignored.
      Received: should not be parsed from body
    RAW
    h = EmailHeaderParser.new(raw).analyze[:headers]
    assert_equal "Alice <alice@ex.com>", h["from"]
    assert_equal "multi line subject", h["subject"]
    assert h.key?("x-body-should-be")  # within the header block (before blank line)
    assert_nil h["received"]           # the only Received line is in the body -> not parsed
  end

  test "collects repeated Received headers into an ordered array" do
    raw = <<~RAW
      Received: from a by b; Wed, 14 Jun 2026 10:00:00 -0700
      Received: from c by d; Wed, 14 Jun 2026 10:01:00 -0700
      From: x@y.com
    RAW
    h = EmailHeaderParser.new(raw).analyze[:headers]
    assert_equal 2, h["received"].size
    assert_match(/from a by b/, h["received"].first)
  end

  test "returns ok:false when no recognizable headers are present" do
    assert_not EmailHeaderParser.new("just some random text\nno colons here").analyze[:ok]
  end
end
