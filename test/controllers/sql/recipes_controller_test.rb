require "test_helper"
require "tmpdir"

class Sql::RecipesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @tmp_config = Dir.mktmpdir("th-sql-recipes-")
    @prev_env   = ENV["TOOLHARNESS_CONFIG_DIR"]
    ENV["TOOLHARNESS_CONFIG_DIR"] = @tmp_config
  end

  teardown do
    ENV["TOOLHARNESS_CONFIG_DIR"] = @prev_env
    FileUtils.remove_entry(@tmp_config)
  end

  test "GET index renders the palette with all 6 starters and no saved" do
    get sql_recipes_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    # All 6 starters listed:
    assert_match "SHOW TABLES",        response.body
    assert_match "SHOW DATABASES",     response.body
    assert_match "SHOW CREATE TABLE",  response.body
    assert_match "SELECT VERSION()",   response.body
    assert_match "SHOW PROCESSLIST",   response.body
    assert_match "SHOW VARIABLES",     response.body
    # Empty-state hint for saved section:
    assert_match ":save-recipe", response.body
  end

  test "POST create with valid name and sql persists a saved recipe" do
    post sql_recipes_path, params: { name: "find-by-id", sql: "SELECT * FROM t WHERE id = <id>;" },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    fresh = ToolHarness::Sql::RecipeStore.new
    assert fresh.exists?(name: "find-by-id")
    assert_match "find-by-id", response.body
  end

  test "POST create rejects bad name with 422 and no persistence" do
    post sql_recipes_path, params: { name: "Bad Name!", sql: "SELECT 1;" },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :unprocessable_entity
    refute ToolHarness::Sql::RecipeStore.new.exists?(name: "Bad Name!")
  end

  test "POST create rejects empty sql with 422" do
    post sql_recipes_path, params: { name: "ok-name", sql: "   " },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :unprocessable_entity
  end

  test "POST create returns 409 conflict when name exists and confirm=false" do
    ToolHarness::Sql::RecipeStore.new.save(name: "dup", sql: "SELECT 1;")
    post sql_recipes_path, params: { name: "dup", sql: "SELECT 2;" },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :conflict
    assert_equal "SELECT 1;", ToolHarness::Sql::RecipeStore.new.all
                                .find { |r| r[:name] == "dup" && r[:source] == :saved }[:sql]
  end

  test "POST create with confirm=true overwrites an existing saved recipe" do
    ToolHarness::Sql::RecipeStore.new.save(name: "dup", sql: "SELECT 1;")
    post sql_recipes_path, params: { name: "dup", sql: "SELECT 2;", confirm: "true" },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_equal "SELECT 2;", ToolHarness::Sql::RecipeStore.new.all
                                .find { |r| r[:name] == "dup" && r[:source] == :saved }[:sql]
  end

  test "DELETE by name removes a saved recipe" do
    ToolHarness::Sql::RecipeStore.new.save(name: "to-go", sql: "SELECT 1;")
    delete sql_recipe_path(name: "to-go"), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    refute ToolHarness::Sql::RecipeStore.new.exists?(name: "to-go")
  end

  test "DELETE of a starter returns 422 (cannot delete starters)" do
    delete sql_recipe_path(name: "SHOW TABLES"), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :unprocessable_entity
  end
end
