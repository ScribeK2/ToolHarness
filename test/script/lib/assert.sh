# Tiny assertion harness for bash tests. Source it; call assertions; print summary.
# Designed for: testing pure bash functions, no test-runner deps.

THTEST_PASS=0
THTEST_FAIL=0
THTEST_NAME=""

thtest_begin() { THTEST_NAME="$1"; }

thtest_pass() {
  THTEST_PASS=$((THTEST_PASS+1))
  printf '  \033[32mok\033[0m %s\n' "$THTEST_NAME"
}

thtest_fail() {
  THTEST_FAIL=$((THTEST_FAIL+1))
  printf '  \033[31mFAIL\033[0m %s: %s\n' "$THTEST_NAME" "$1"
}

assert_equal() { # expected actual
  if [ "$1" = "$2" ]; then thtest_pass
  else thtest_fail "expected '$1', got '$2'"
  fi
}

assert_true() { # cmd-string
  if eval "$1" >/dev/null 2>&1; then thtest_pass
  else thtest_fail "expected true: $1"
  fi
}

assert_false() { # cmd-string
  if ! eval "$1" >/dev/null 2>&1; then thtest_pass
  else thtest_fail "expected false: $1"
  fi
}

assert_contains() { # haystack needle
  case "$1" in
    *"$2"*) thtest_pass ;;
    *)      thtest_fail "'$1' does not contain '$2'" ;;
  esac
}

thtest_summary() {
  printf '\n%d passed, %d failed\n' "$THTEST_PASS" "$THTEST_FAIL"
  [ "$THTEST_FAIL" -eq 0 ]
}
