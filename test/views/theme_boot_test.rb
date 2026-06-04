require "test_helper"

class ThemeBootTest < ActionView::TestCase
  test "boot partial embeds the scheme map and default key" do
    render "layouts/theme_boot"
    assert_includes rendered, %("nord":"dark")
    assert_includes rendered, %("catppuccin-latte":"light")
    assert_includes rendered, "tokyonight-storm"
  end

  test "boot partial falls back to default for unknown keys" do
    render "layouts/theme_boot"
    # The validation line that guarantees an unknown/missing key -> default.
    assert_includes rendered, "SCHEMES[key]"
    assert_includes rendered, "DEFAULT"
    assert_includes rendered, %("tokyonight-storm")
  end

  test "boot partial sets data-theme and colorScheme before paint" do
    render "layouts/theme_boot"
    assert_includes rendered, "el.dataset.theme"
    assert_includes rendered, "el.style.colorScheme"
  end
end
