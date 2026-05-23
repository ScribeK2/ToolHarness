require "test_helper"
require "tool_harness/sql/limit_injector"

class ToolHarness::Sql::LimitInjectorTest < ActiveSupport::TestCase
  L = ToolHarness::Sql::LimitInjector

  test "appends LIMIT to plain SELECT without LIMIT" do
    out = L.append("SELECT * FROM domains", 500)
    assert_equal "SELECT * FROM domains LIMIT 500", out.fetch(:sql)
    assert out.fetch(:injected)
  end

  test "preserves trailing semicolon" do
    out = L.append("SELECT 1;", 500)
    assert_equal "SELECT 1 LIMIT 500;", out.fetch(:sql)
    assert out.fetch(:injected)
  end

  test "leaves SELECT-with-LIMIT untouched" do
    out = L.append("SELECT * FROM domains LIMIT 10", 500)
    assert_equal "SELECT * FROM domains LIMIT 10", out.fetch(:sql)
    refute out.fetch(:injected)
  end

  test "appends LIMIT for CTE ending in SELECT" do
    out = L.append("WITH t AS (SELECT 1) SELECT * FROM t", 500)
    assert_equal "WITH t AS (SELECT 1) SELECT * FROM t LIMIT 500", out.fetch(:sql)
    assert out.fetch(:injected)
  end

  test "does not touch SHOW / DESC / EXPLAIN / USE" do
    %w[SHOW\ TABLES DESC\ foo EXPLAIN\ SELECT\ 1 USE\ foo].each do |s|
      out = L.append(s, 500)
      assert_equal s, out.fetch(:sql)
      refute out.fetch(:injected)
    end
  end

  test "does not touch write statements" do
    out = L.append("UPDATE foo SET bar = 1 WHERE id = 1", 500)
    refute out.fetch(:injected)
    assert_equal "UPDATE foo SET bar = 1 WHERE id = 1", out.fetch(:sql)
  end

  test "treats LIMIT inside string as not present" do
    sql = "SELECT 'use LIMIT 5 here' AS note"
    out = L.append(sql, 500)
    assert out.fetch(:injected)
    assert_equal "SELECT 'use LIMIT 5 here' AS note LIMIT 500", out.fetch(:sql)
  end
end
