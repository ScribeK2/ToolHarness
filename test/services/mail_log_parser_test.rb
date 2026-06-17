require "test_helper"

class MailLogParserTest < ActiveSupport::TestCase
  SENT = <<~LOG
    2026-06-12T02:26:20.123Z mail01 postfix/smtpd[2811]: A1B2C3D4: client=mail.client.com[203.0.113.10]
    2026-06-12T02:26:20.200Z mail01 postfix/cleanup[2815]: A1B2C3D4: message-id=<abc123@client.com>
    2026-06-12T02:26:20.250Z mail01 postfix/qmgr[2790]: A1B2C3D4: from=<sender@client.com>, size=4523, nrcpt=1 (queue active)
    2026-06-12T02:26:21.500Z mail01 postfix/smtp[2820]: A1B2C3D4: to=<rcpt@example.net>, relay=mx.example.net[198.51.100.5]:25, delay=1.3, dsn=2.0.0, status=sent (250 2.0.0 OK 1A2B3C)
    2026-06-12T02:26:21.600Z mail01 postfix/qmgr[2790]: A1B2C3D4: removed
  LOG

  test "garbage input returns ok:false without raising" do
    res = MailLogParser.new("not a log at all\n\n").analyze
    assert_equal false, res[:ok]
    assert_empty res[:messages]
    assert_empty res[:rejections]
  end

  test "empty input returns ok:false" do
    assert_equal false, MailLogParser.new("").analyze[:ok]
    assert_equal false, MailLogParser.new(nil).analyze[:ok]
  end

  test "reconstructs a delivered message grouped by queue id" do
    res = MailLogParser.new(SENT).analyze
    assert res[:ok]
    assert_equal 1, res[:messages].size
    m = res[:messages].first
    assert_equal "A1B2C3D4", m[:queue_id]
    assert_equal "sender@client.com", m[:from]
    assert_equal "mail.client.com", m[:client_host]
    assert_equal "203.0.113.10", m[:client_ip]
    assert_equal "<abc123@client.com>", m[:message_id]
    assert_equal 4523, m[:size]
    assert_equal 1, m[:nrcpt]
    assert m[:removed]
    assert_equal 1, m[:recipients].size
    r = m[:recipients].first
    assert_equal "rcpt@example.net", r[:to]
    assert_equal "mx.example.net", r[:relay_host]
    assert_equal "198.51.100.5", r[:relay_ip]
    assert_equal "sent", r[:status]
    assert_equal "2.0.0", r[:dsn]
    assert_equal false, r[:local]
    assert_equal "250 2.0.0 OK 1A2B3C", r[:reply]
    assert_equal "DELIVERED", m[:verdict]
  end

  test "bounced message gets BOUNCED verdict and keeps raw reply" do
    log = "Jun 12 02:30:00 mail01 postfix/smtp[2820]: B2C3D4E5: to=<nobody@example.net>, relay=mx.example.net[198.51.100.5]:25, delay=0.9, dsn=5.1.1, status=bounced (host mx.example.net[198.51.100.5] said: 550 5.1.1 <nobody@example.net>: Recipient address rejected: User unknown (in reply to RCPT TO command))"
    m = MailLogParser.new(log).analyze[:messages].first
    assert_equal "BOUNCED", m[:verdict]
    assert_equal "bounced", m[:recipients].first[:status]
    assert_includes m[:recipients].first[:reply], "550 5.1.1"
    assert_equal "5.1.1", m[:recipients].first[:dsn]
  end

  test "deferred message gets DEFERRED verdict" do
    log = "2026-06-12T02:40:00Z mail01 postfix/smtp[2820]: C3D4E5F6: to=<user@example.org>, relay=mx.example.org[192.0.2.7]:25, delay=2.1, dsn=4.7.1, status=deferred (host mx.example.org[192.0.2.7] said: 451 4.7.1 Greylisting in effect, please try again later)"
    m = MailLogParser.new(log).analyze[:messages].first
    assert_equal "DEFERRED", m[:verdict]
  end

  test "dovecot LMTP local delivery is flagged local and DELIVERED" do
    log = "2026-06-12T02:50:00Z mail01 postfix/lmtp[3001]: D4E5F6A1: to=<local@ourdomain.com>, relay=ourdomain.com[private/dovecot-lmtp], delay=0.1, dsn=2.0.0, status=sent (250 2.0.0 <local@ourdomain.com> Saved)"
    m = MailLogParser.new(log).analyze[:messages].first
    assert_equal "DELIVERED", m[:verdict]
    assert_equal true, m[:recipients].first[:local]
  end

  test "NOQUEUE reject is collected as a rejection" do
    log = "Jun 12 03:00:00 mail01 postfix/smtpd[2811]: NOQUEUE: reject: RCPT from unknown[185.220.101.1]: 554 5.7.1 Service unavailable; Client host [185.220.101.1] blocked using zen.spamhaus.org; from=<spammer@bad.com> to=<victim@ourdomain.com> proto=ESMTP helo=<bad.com>"
    res = MailLogParser.new(log).analyze
    assert res[:ok]
    assert_equal 1, res[:rejections].size
    rej = res[:rejections].first
    assert_equal "185.220.101.1", rej[:client_ip]
    assert_equal "victim@ourdomain.com", rej[:to]
    assert_equal "spammer@bad.com", rej[:from]
    assert_equal "554", rej[:code]
    assert_includes rej[:reply], "zen.spamhaus.org"
  end

  test "multiple recipients with mixed outcomes under one queue id => BOUNCED" do
    log = <<~LOG
      postfix/qmgr[2790]: AA11BB22: from=<s@client.com>, size=10, nrcpt=2 (queue active)
      postfix/smtp[2820]: AA11BB22: to=<ok@example.net>, relay=mx.example.net[198.51.100.5]:25, dsn=2.0.0, status=sent (250 OK)
      postfix/smtp[2820]: AA11BB22: to=<bad@example.net>, relay=mx.example.net[198.51.100.5]:25, dsn=5.1.1, status=bounced (550 5.1.1 User unknown)
    LOG
    m = MailLogParser.new(log).analyze[:messages].first
    assert_equal 2, m[:recipients].size
    assert_equal "BOUNCED", m[:verdict]
  end

  test "interleaved lines from two queue ids regroup correctly" do
    log = <<~LOG
      postfix/qmgr[2790]: QID0001A: from=<a@client.com>, size=10, nrcpt=1 (queue active)
      postfix/qmgr[2790]: QID0002B: from=<b@client.com>, size=20, nrcpt=1 (queue active)
      postfix/smtp[2820]: QID0001A: to=<x@example.net>, relay=mx[198.51.100.5]:25, dsn=2.0.0, status=sent (250 OK)
      postfix/smtp[2820]: QID0002B: to=<y@example.net>, relay=mx[198.51.100.5]:25, dsn=5.1.1, status=bounced (550 User unknown)
    LOG
    res = MailLogParser.new(log).analyze
    assert_equal 2, res[:messages].size
    verdicts = res[:messages].map { |m| [m[:queue_id], m[:verdict]] }.to_h
    assert_equal "DELIVERED", verdicts["QID0001A"]
    assert_equal "BOUNCED", verdicts["QID0002B"]
  end

  test "queue id with no terminal status => INCOMPLETE" do
    log = "postfix/qmgr[2790]: TRUNC123: from=<a@client.com>, size=10, nrcpt=1 (queue active)"
    m = MailLogParser.new(log).analyze[:messages].first
    assert_equal "INCOMPLETE", m[:verdict]
  end

  test "counts lines it cannot recognize" do
    log = "this is noise\npostfix/qmgr[1]: ZZ99: from=<a@b.com>, size=1, nrcpt=1 (queue active)\nmore noise"
    res = MailLogParser.new(log).analyze
    assert_equal 2, res[:unparsed_count]
  end
end
