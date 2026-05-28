require "test_helper"

class ToolHarness::HostNormalizerTest < ActiveSupport::TestCase
  # Each row: [input, preserve_path:false expected, preserve_path:true expected]
  CASES = [
    ["https://example.com",                "example.com",            "example.com"],
    ["http://example.com",                 "example.com",            "example.com"],
    ["HTTPS://Example.com",                "Example.com",            "Example.com"],
    ["https://example.com/",               "example.com",            "example.com"],
    ["http://example.com/foo/bar",         "example.com",            "example.com/foo/bar"],
    ["https://example.com/foo?x=1#y",      "example.com",            "example.com/foo?x=1#y"],
    ["  https://example.com  ",            "example.com",            "example.com"],
    ["  HTTPS://Example.com/  ",           "Example.com",            "Example.com"],
    ["example.com:8080",                   "example.com:8080",       "example.com:8080"],
    ["example.com:8080/admin",             "example.com:8080",       "example.com:8080/admin"],
    ["ftp://example.com",                  "ftp://example.com",      "ftp://example.com"],
    ["ftp://example.com/path",             "ftp://example.com/path", "ftp://example.com/path"],
    ["example.com",                        "example.com",            "example.com"],
    ["example.com/foo/",                   "example.com",            "example.com/foo"],
    ["",                                   "",                       ""],
  ].freeze

  CASES.each do |input, expected_strip, expected_preserve|
    test "normalizes #{input.inspect} with preserve_path:false to #{expected_strip.inspect}" do
      assert_equal expected_strip, ToolHarness::HostNormalizer.call(input)
    end

    test "normalizes #{input.inspect} with preserve_path:true to #{expected_preserve.inspect}" do
      assert_equal expected_preserve, ToolHarness::HostNormalizer.call(input, preserve_path: true)
    end
  end

  test "treats nil as empty string" do
    assert_equal "", ToolHarness::HostNormalizer.call(nil)
    assert_equal "", ToolHarness::HostNormalizer.call(nil, preserve_path: true)
  end

  test "is idempotent for preserve_path:false" do
    CASES.each do |input, _, _|
      once  = ToolHarness::HostNormalizer.call(input)
      twice = ToolHarness::HostNormalizer.call(once)
      assert_equal once, twice, "not idempotent for #{input.inspect}"
    end
  end

  test "is idempotent for preserve_path:true" do
    CASES.each do |input, _, _|
      once  = ToolHarness::HostNormalizer.call(input,  preserve_path: true)
      twice = ToolHarness::HostNormalizer.call(once,   preserve_path: true)
      assert_equal once, twice, "not idempotent (preserve_path) for #{input.inspect}"
    end
  end
end
