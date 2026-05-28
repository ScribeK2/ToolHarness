require "test_helper"

class PropagationCheckerTest < ActiveSupport::TestCase
  test "RESOLVERS has 20 entries, each with id/ip/operator/region" do
    list = PropagationChecker::RESOLVERS
    assert_equal 20, list.size
    list.each do |r|
      assert r[:id].is_a?(String) && !r[:id].empty?, "missing id: #{r.inspect}"
      assert r[:ip] =~ /\A\d{1,3}(\.\d{1,3}){3}\z/, "bad ip: #{r.inspect}"
      assert r[:operator].is_a?(String) && !r[:operator].empty?
      assert r[:region].is_a?(String) && !r[:region].empty?
    end
  end

  test "RESOLVERS ids are unique" do
    ids = PropagationChecker::RESOLVERS.map { |r| r[:id] }
    assert_equal ids.uniq.size, ids.size, "duplicate resolver ids: #{ids - ids.uniq}"
  end

  test "RESOLVERS is frozen" do
    assert PropagationChecker::RESOLVERS.frozen?
  end
end
