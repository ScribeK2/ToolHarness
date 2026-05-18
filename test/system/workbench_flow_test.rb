require "application_system_test_case"

class WorkbenchFlowTest < ApplicationSystemTestCase
  setup do
    @user = User.create!(email: "sys@test", password: "password123")
  end

  test "user signs in, runs whois, sees streaming result" do
    visit new_user_session_path
    fill_in "email",    with: @user.email
    fill_in "password", with: "password123"
    click_button "SIGN IN ⏎"

    assert_text "▸ Ready."
    assert_selector "[data-mode-badge]", text: "NORMAL"

    # Switch to whois via rail
    first(".rail-item[data-tool-key='whois_lookup']").click

    # Type target and run
    fill_in "tool_run[domain]", with: "example.com"
    find("button[type=submit]", text: /RUN/).click

    # Result begins streaming
    assert_text "running", wait: 5
    # Wait for completion
    assert_text "done", wait: 30
    # Mode badge still says NORMAL
    assert_selector "[data-mode-badge]", text: "NORMAL"
  end
end
