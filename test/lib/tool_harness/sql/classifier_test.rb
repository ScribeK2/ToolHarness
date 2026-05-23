require "test_helper"
require "tool_harness/sql/classifier"

class ToolHarness::Sql::ClassifierTest < ActiveSupport::TestCase
  C = ToolHarness::Sql::Classifier

  test "blank input is unknown" do
    assert_equal :unknown, C.classify("")
    assert_equal :unknown, C.classify("   \n  ")
  end

  test "leading whitespace and line comments are stripped" do
    sql = <<~SQL
      -- ticket #1
      /* multi
         line */
        SELECT 1
    SQL
    assert_equal :read, C.classify(sql)
  end

  test "read statements" do
    %w[SELECT SHOW EXPLAIN DESC DESCRIBE USE].each do |kw|
      assert_equal :read, C.classify("#{kw} foo"), "#{kw} should be :read"
    end
  end

  test "CTE that ends in SELECT is read" do
    assert_equal :read, C.classify("WITH t AS (SELECT 1) SELECT * FROM t")
  end

  test "CTE that ends in DELETE is write_safe (has WHERE) or write_dangerous (no WHERE)" do
    assert_equal :write_safe, C.classify("WITH t AS (SELECT 1) DELETE FROM x WHERE id IN (SELECT 1 FROM t)")
    assert_equal :write_dangerous, C.classify("WITH t AS (SELECT 1) DELETE FROM x")
  end

  test "INSERT / REPLACE are write_safe" do
    assert_equal :write_safe, C.classify("INSERT INTO foo (id) VALUES (1)")
    assert_equal :write_safe, C.classify("REPLACE INTO foo SET id = 1")
  end

  test "UPDATE/DELETE with WHERE are write_safe; without WHERE are write_dangerous" do
    assert_equal :write_safe,      C.classify("UPDATE foo SET bar = 1 WHERE id = 2")
    assert_equal :write_dangerous, C.classify("UPDATE foo SET bar = 1")
    assert_equal :write_safe,      C.classify("DELETE FROM foo WHERE id = 1")
    assert_equal :write_dangerous, C.classify("DELETE FROM foo")
  end

  test "WHERE inside a string literal does NOT count as WHERE" do
    sql = "UPDATE foo SET note = 'set WHERE id = 5'"
    assert_equal :write_dangerous, C.classify(sql)
  end

  test "WHERE inside a comment does NOT count as WHERE" do
    sql = "UPDATE foo SET bar = 1 -- WHERE id = 1"
    assert_equal :write_dangerous, C.classify(sql)
  end

  test "DDL is write_dangerous" do
    %w[DROP TRUNCATE ALTER RENAME GRANT REVOKE CALL].each do |kw|
      assert_equal :write_dangerous, C.classify("#{kw} TABLE foo"), "#{kw} should be :write_dangerous"
    end
    assert_equal :write_dangerous, C.classify("LOAD DATA INFILE 'x' INTO TABLE foo")
  end

  test "unrecognized leading keyword is unknown" do
    assert_equal :unknown, C.classify("BANANA fruit")
  end

  test "multi-statement is unknown (split-by-; trips multiple verbs)" do
    assert_equal :unknown, C.classify("SELECT 1; SELECT 2")
  end
end
