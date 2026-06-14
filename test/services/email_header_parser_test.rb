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

  test "builds a chronological timeline with per-hop delay and total transit" do
    raw = <<~RAW
      Received: from relay.ex.com (relay.ex.com [203.0.113.9]) by mx.dest.com with ESMTPS id Z2; Wed, 14 Jun 2026 10:02:00 -0700
      Received: from sender.ex.com (sender.ex.com [203.0.113.5]) by relay.ex.com with ESMTP id Z1 for <u@dest.com>; Wed, 14 Jun 2026 10:00:00 -0700
      From: a@ex.com
    RAW
    t = EmailHeaderParser.new(raw).analyze[:timeline]
    # chronological: oldest (sender->relay) first
    assert_equal "sender.ex.com", t[:hops].first[:from_host]
    assert_equal "203.0.113.5", t[:hops].first[:from_ip]
    assert_equal "ESMTP", t[:hops].first[:with]
    assert_nil t[:hops].first[:delay_s]            # first hop has no predecessor
    assert_equal 120.0, t[:hops].last[:delay_s]    # 2 minutes between hops
    assert_equal 120.0, t[:total_transit_s]
    assert_equal 0, t[:originating_index]          # first public IP
  end

  test "private/loopback source IPs do not count as the originating hop" do
    raw = <<~RAW
      Received: from gw (gw [203.0.113.5]) by mx; Wed, 14 Jun 2026 10:01:00 -0700
      Received: from localhost (localhost [127.0.0.1]) by gw; Wed, 14 Jun 2026 10:00:00 -0700
      From: a@ex.com
    RAW
    t = EmailHeaderParser.new(raw).analyze[:timeline]
    assert_equal 1, t[:originating_index]          # skip the 127.0.0.1 hop
    assert_equal "203.0.113.5", EmailHeaderParser.new(raw).analyze[:origin_ip]
  end

  test "parses spf/dkim/dmarc/compauth from Authentication-Results" do
    raw = <<~RAW
      Authentication-Results: mx.dest.com; spf=pass smtp.mailfrom=ex.com; dkim=pass header.d=ex.com; dmarc=fail (p=reject) header.from=ex.com; compauth=fail reason=001
      From: a@ex.com
    RAW
    a = EmailHeaderParser.new(raw).analyze[:auth]
    assert_equal "pass", a[:spf]
    assert_equal "pass", a[:dkim]
    assert_equal "fail", a[:dmarc]
    assert_equal "fail", a[:compauth]
  end

  test "auth verdicts are nil when the header is absent" do
    a = EmailHeaderParser.new("From: a@ex.com\nReceived: from a by b; Wed, 14 Jun 2026 10:00:00 -0700").analyze[:auth]
    assert_nil a[:spf]
    assert_nil a[:dmarc]
  end
end
