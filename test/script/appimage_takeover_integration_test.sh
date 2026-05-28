#!/bin/bash
# Integration tests for AppRun-takeover.sh — real flock, real $TH_STATE in tmp dirs, real PIDs.
# Each test sets up its own tmp dir and tears down the fake holder it spawned.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/assert.sh"
. "$HERE/../../script/AppRun-takeover.sh"

# Helper: spawn a backgrounded "fake old AppRun" that:
#   - opens fd 9 on $1 and acquires flock
#   - writes its own $BASHPID to "$tmp_dir/running_pid"
#   - optionally ignores SIGTERM (for the SIGKILL-fallback test)
#   - sleeps until killed
# Returns the holder's PID via echo (so callers can `pid=$(spawn_fake_holder ...)`).
# Args: lock_file pid_file [--ignore-sigterm]
spawn_fake_holder() {
  local lock_file="$1" pid_file="$2" ignore_sigterm="${3:-}"
  : > "$pid_file"  # truncate; we wait for non-empty
  (
    exec 9>"$lock_file"
    flock -n 9
    echo "$BASHPID" > "$pid_file"
    if [ "$ignore_sigterm" = "--ignore-sigterm" ]; then
      trap '' TERM
    else
      trap 'exit 0' TERM
    fi
    # `wait $!` on a backgrounded sleep is reliably trap-interruptible.
    # Close fd 9 in the sleep child so it does not hold the lock on its own.
    sleep 60 9>&- &
    wait $!
  ) >/dev/null 2>/dev/null &
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    if [ -s "$pid_file" ]; then
      cat "$pid_file"
      return 0
    fi
    sleep 0.1
  done
  echo "spawn_fake_holder: holder did not write PID within 1s" >&2
  return 1
}

# Helper: ensure no leftover holder process lingers between tests.
kill_holder() {
  local pid="$1"
  kill -KILL "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

# ---- takeover: SIGTERM happy path ----
TMP_DIR=$(mktemp -d)
TH_STATE="$TMP_DIR"
LOCK_FILE="$TMP_DIR/lock"
holder_pid=$(spawn_fake_holder "$LOCK_FILE" "$TMP_DIR/running_pid")
exec 9>"$LOCK_FILE"  # open our own fd 9; takeover uses it

thtest_begin "takeover returns 0 when holder exits on SIGTERM"
if takeover; then thtest_pass; else thtest_fail "takeover returned non-zero"; fi

sleep 0.1  # let kernel reap the killed process
thtest_begin "old holder process is gone after SIGTERM-takeover"
if kill -0 "$holder_pid" 2>/dev/null; then
  thtest_fail "holder pid $holder_pid still alive"
  kill_holder "$holder_pid"
else
  thtest_pass
fi

exec 9<&-
rm -rf "$TMP_DIR"

# ---- takeover: SIGKILL fallback when holder ignores SIGTERM ----
TMP_DIR=$(mktemp -d)
TH_STATE="$TMP_DIR"
LOCK_FILE="$TMP_DIR/lock"
holder_pid=$(spawn_fake_holder "$LOCK_FILE" "$TMP_DIR/running_pid" --ignore-sigterm)
exec 9>"$LOCK_FILE"

thtest_begin "takeover returns 0 via SIGKILL when SIGTERM is ignored"
stderr_log="$TMP_DIR/stderr.log"
APPRUN_SIGTERM_GRACE_SECS=1 takeover 2>"$stderr_log"
result=$?
if [ "$result" -eq 0 ]; then thtest_pass; else thtest_fail "takeover returned $result"; fi

thtest_begin "takeover stderr warns about forcing kill"
assert_contains "$(cat "$stderr_log")" "did not exit within"

thtest_begin "old (SIGTERM-ignoring) holder is gone after SIGKILL"
sleep 0.1
if kill -0 "$holder_pid" 2>/dev/null; then
  thtest_fail "holder pid $holder_pid still alive after SIGKILL"
  kill_holder "$holder_pid"
else
  thtest_pass
fi

exec 9<&-
rm -rf "$TMP_DIR"

# ---- takeover: missing running_pid file (stale/legacy state) ----
TMP_DIR=$(mktemp -d)
TH_STATE="$TMP_DIR"
LOCK_FILE="$TMP_DIR/lock"
holder_pid=$(spawn_fake_holder "$LOCK_FILE" "$TMP_DIR/running_pid")
rm -f "$TMP_DIR/running_pid"  # simulate legacy / missing file
exec 9>"$LOCK_FILE"

stderr_log="$TMP_DIR/stderr.log"
takeover 2>"$stderr_log"
result=$?

thtest_begin "takeover exits non-zero when lock is held but PID unknown"
assert_equal "1" "$result"

thtest_begin "stderr mentions stale or missing"
assert_contains "$(cat "$stderr_log")" "stale or missing"

exec 9<&-
kill_holder "$holder_pid"
rm -rf "$TMP_DIR"

thtest_summary
