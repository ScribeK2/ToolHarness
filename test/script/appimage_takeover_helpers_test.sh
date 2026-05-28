#!/bin/bash
# Unit tests for AppRun-takeover.sh helpers.
# These exercise pure functions only — no real flock, no real /proc/locks.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/assert.sh"
. "$HERE/../../script/AppRun-takeover.sh"

# ---- ver_lt ----
thtest_begin "ver_lt 0.4.1 < 0.4.2 → true"
assert_true 'ver_lt "0.4.1" "0.4.2"'

thtest_begin "ver_lt 0.4.2 < 0.4.1 → false"
assert_false 'ver_lt "0.4.2" "0.4.1"'

thtest_begin "ver_lt 0.4.10 < 0.4.2 → false (version-sort, not lex)"
assert_false 'ver_lt "0.4.10" "0.4.2"'

thtest_begin "ver_lt 0.4.2 < 0.4.10 → true"
assert_true 'ver_lt "0.4.2" "0.4.10"'

thtest_begin "ver_lt 0.4.2 < 0.4.2 → false (equal)"
assert_false 'ver_lt "0.4.2" "0.4.2"'

thtest_begin "ver_lt 0.5.0 < 1.0.0 → true"
assert_true 'ver_lt "0.5.0" "1.0.0"'

thtest_summary
