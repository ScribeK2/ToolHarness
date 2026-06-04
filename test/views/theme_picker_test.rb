require "test_helper"

class ThemePickerTest < ActionView::TestCase
  test "renders a row for every registered theme with metadata" do
    render "workbench/theme_picker"
    ToolHarness::Themes.all.each do |t|
      assert_includes rendered, %(data-key="#{t[:key]}")
      assert_includes rendered, t[:label]
    end
  end

  test "rows carry scheme and a swatch scoped to the theme" do
    render "workbench/theme_picker"
    assert_includes rendered, %(data-scheme="dark")
    assert_includes rendered, %(data-scheme="light")
    # Swatch wrapper scopes data-theme so CSS fills it — no color literals here.
    assert_includes rendered, %(data-theme="#{ToolHarness::Themes.all.first[:key]}")
  end

  test "overlay is hidden by default and is a theme-picker row target" do
    render "workbench/theme_picker"
    assert_includes rendered, "hidden"
    assert_includes rendered, %(data-theme-picker-target="row")
    assert_includes rendered, %(data-theme-picker-target="overlay")
  end
end
