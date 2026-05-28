#!/bin/bash
# Self-test for the assertion harness.
set -u
cd "$(dirname "$0")"
. ./assert.sh

thtest_begin "assert_equal passes on equal strings"
assert_equal "foo" "foo"

thtest_begin "assert_true passes on true"
assert_true 'true'

thtest_begin "assert_false passes on false"
assert_false 'false'

thtest_begin "assert_contains passes when needle in haystack"
assert_contains "hello world" "lo wo"

thtest_summary
