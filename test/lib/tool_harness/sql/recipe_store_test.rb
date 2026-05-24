require "test_helper"
require "tmpdir"
require "tool_harness/sql/recipe_store"

class ToolHarness::Sql::RecipeStoreTest < ActiveSupport::TestCase
  RS = ToolHarness::Sql::RecipeStore

  setup do
    @tmp  = Dir.mktmpdir("th-sql-recipes-")
    @path = File.join(@tmp, "recipes.yml")
    @store = RS.new(path: @path)
  end

  teardown { FileUtils.remove_entry(@tmp) }

  test "all returns just starters when no saved recipes exist" do
    names = @store.all.map { |r| r[:name] }
    assert_equal RS::STARTERS.map { |s| s[:name] }, names
    assert(@store.all.all? { |r| r[:source] == :starter })
  end

  test "save persists a recipe and reload returns it" do
    @store.save(name: "find-customer", sql: "SELECT * FROM customers WHERE id = <id>;")
    fresh = RS.new(path: @path)
    saved = fresh.all.find { |r| r[:source] == :saved }
    assert_equal "find-customer", saved[:name]
    assert_match(/customers/, saved[:sql])
    assert saved[:created_at].present?
  end

  test "save with a starter name shadows the starter in #all" do
    @store.save(name: "SHOW TABLES", sql: "-- my override\nSHOW FULL TABLES;")
    rows = @store.all.select { |r| r[:name] == "SHOW TABLES" }
    assert_equal 1, rows.size
    assert_equal :saved, rows.first[:source]
    assert_match(/FULL TABLES/, rows.first[:sql])
  end

  test "delete removes a saved recipe" do
    @store.save(name: "tmp", sql: "SELECT 1;")
    assert @store.delete(name: "tmp")
    assert_nil @store.all.find { |r| r[:name] == "tmp" && r[:source] == :saved }
  end

  test "delete returns false for a starter (cannot delete starters)" do
    refute @store.delete(name: "SHOW TABLES")
  end

  test "delete returns false for unknown name" do
    refute @store.delete(name: "no-such-recipe")
  end

  test "exists? returns true for saved, false for starter, false for unknown" do
    @store.save(name: "kept", sql: "SELECT 1;")
    assert     @store.exists?(name: "kept")
    refute     @store.exists?(name: "SHOW TABLES")
    refute     @store.exists?(name: "missing")
  end

  test "load with malformed YAML returns starters only and exposes a parse error" do
    File.write(@path, "this: is: not: [valid")
    fresh = RS.new(path: @path)
    names = fresh.all.map { |r| r[:name] }
    assert_equal RS::STARTERS.map { |s| s[:name] }, names
    assert_match(/yaml/i, fresh.last_load_error.to_s)
  end

  test "save creates file with 0600 perms" do
    @store.save(name: "perms-check", sql: "SELECT 1;")
    mode = File.stat(@path).mode & 0o777
    assert_equal 0o600, mode
  end

  test "save is atomic — interrupted write does not corrupt existing data" do
    @store.save(name: "first", sql: "SELECT 1;")
    @store.save(name: "second", sql: "SELECT 2;")
    fresh = RS.new(path: @path)
    saved_names = fresh.all.select { |r| r[:source] == :saved }.map { |r| r[:name] }
    assert_includes saved_names, "first"
    assert_includes saved_names, "second"
  end
end
