require "test_helper"

class SqlWorkbenchSourceRegressionTest < ActiveSupport::TestCase
  FILES = %w[
    app/services/tools/sql_workbench.rb
    app/controllers/sql/queries_controller.rb
    app/controllers/sql/sessions_controller.rb
    app/controllers/sql/profiles_controller.rb
    app/controllers/sql/history_controller.rb
    app/controllers/sql/cells_controller.rb
    app/controllers/sql/recipes_controller.rb
    lib/tool_harness/sql/classifier.rb
    lib/tool_harness/sql/limit_injector.rb
    lib/tool_harness/sql/secret_box.rb
    lib/tool_harness/sql/connection_store.rb
    lib/tool_harness/sql/recipe_store.rb
    lib/tool_harness/sql/runner.rb
    lib/tool_harness/sql/result.rb
  ].freeze

  FILES.each do |relpath|
    test "#{relpath} does not shell out" do
      src = File.read(Rails.root.join(relpath))
      refute_match(/Open3/,             src, "#{relpath} must not use Open3")
      refute_match(/\bsystem\s*\(/,     src, "#{relpath} must not call system(")
      refute_match(/`[^`\n]*`/m,        src, "#{relpath} must not use backtick shellout")
    end
  end
end
