require "test_helper"

class ToolHarness::ThemesTest < ActiveSupport::TestCase
  test "all returns ordered list of symbol-keyed hashes" do
    all = ToolHarness::Themes.all
    assert all.size >= 11
    first = all.first
    assert_equal "tokyonight-storm", first[:key] # keys are strings
    assert first.key?(:label)
    assert first.key?(:scheme)
  end

  test "keys returns every theme key as a string" do
    assert_includes ToolHarness::Themes.keys, "nord"
    assert_includes ToolHarness::Themes.keys, "catppuccin-latte"
    assert_equal ToolHarness::Themes.keys.uniq, ToolHarness::Themes.keys
  end

  test "default_key is the first entry" do
    assert_equal "tokyonight-storm", ToolHarness::Themes.default_key
  end

  test "scheme_map maps each key to dark or light" do
    map = ToolHarness::Themes.scheme_map
    assert_equal "dark",  map["nord"]
    assert_equal "light", map["catppuccin-latte"]
    assert(map.values.all? { |v| %w[dark light].include?(v) })
  end

  test "every scheme is dark or light" do
    assert(ToolHarness::Themes.all.all? { |t| %w[dark light].include?(t[:scheme]) })
  end
end
