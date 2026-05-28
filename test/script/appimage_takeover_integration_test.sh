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

# ---- appimage_lock_dispatch ----
# Helper: run dispatch in a subshell so its `exit` calls don't kill the test runner.
# Args: <our_version> <th_state> [stdout_log] [stderr_log]
run_dispatch_subshell() {
  local ver="$1" th_state="$2" out="${3:-/dev/null}" err="${4:-/dev/null}"
  (
    OUR_VERSION="$ver"
    TH_STATE="$th_state"
    LOCK_FILE="$th_state/lock"
    surface_url() { :; }  # stub — no browser opening in tests
    appimage_lock_dispatch
  ) >"$out" 2>"$err"
}

# --- Branch A: lock is free → success, writes running_version + running_pid ---
TMP_DIR=$(mktemp -d)
run_dispatch_subshell "0.4.2" "$TMP_DIR" "$TMP_DIR/out" "$TMP_DIR/err"
result=$?
thtest_begin "dispatch returns 0 when lock is free"
assert_equal "0" "$result"
thtest_begin "dispatch writes running_version when it acquires the lock"
assert_equal "0.4.2" "$(cat "$TMP_DIR/running_version" 2>/dev/null)"
thtest_begin "dispatch writes running_pid (non-empty) when it acquires the lock"
pid_written=$(cat "$TMP_DIR/running_pid" 2>/dev/null || echo "")
if [ -n "$pid_written" ]; then thtest_pass; else thtest_fail "running_pid empty or missing"; fi
rm -rf "$TMP_DIR"

# --- Branch B: same version running → exit 0, no kill, files unchanged ---
TMP_DIR=$(mktemp -d)
echo "0.4.2" > "$TMP_DIR/running_version"
echo "3000"  > "$TMP_DIR/port"
holder_pid=$(spawn_fake_holder "$TMP_DIR/lock" "$TMP_DIR/running_pid")
run_dispatch_subshell "0.4.2" "$TMP_DIR" "$TMP_DIR/out" "$TMP_DIR/err"
result=$?
thtest_begin "dispatch exits 0 on same-version collision"
assert_equal "0" "$result"
thtest_begin "dispatch prints 'already running' on same-version"
assert_contains "$(cat "$TMP_DIR/out")" "already running"
thtest_begin "dispatch does NOT kill the holder on same-version"
if kill -0 "$holder_pid" 2>/dev/null; then thtest_pass
else thtest_fail "holder was killed"
fi
thtest_begin "dispatch leaves running_version unchanged on same-version"
assert_equal "0.4.2" "$(cat "$TMP_DIR/running_version")"
kill_holder "$holder_pid"
rm -rf "$TMP_DIR"

# --- Branch C: newer version running → exit 0, refuse-and-warn, no kill ---
TMP_DIR=$(mktemp -d)
echo "0.5.0" > "$TMP_DIR/running_version"
echo "3000"  > "$TMP_DIR/port"
holder_pid=$(spawn_fake_holder "$TMP_DIR/lock" "$TMP_DIR/running_pid")
run_dispatch_subshell "0.4.2" "$TMP_DIR" "$TMP_DIR/out" "$TMP_DIR/err"
result=$?
thtest_begin "dispatch exits 0 on newer-running collision"
assert_equal "0" "$result"
thtest_begin "dispatch warns 'Refusing to downgrade'"
assert_contains "$(cat "$TMP_DIR/err")" "Refusing to downgrade"
thtest_begin "dispatch does NOT kill on newer-running"
if kill -0 "$holder_pid" 2>/dev/null; then thtest_pass
else thtest_fail "holder was killed"
fi
thtest_begin "running_version unchanged on newer-running"
assert_equal "0.5.0" "$(cat "$TMP_DIR/running_version")"
kill_holder "$holder_pid"
rm -rf "$TMP_DIR"

# --- Branch D: older version running → takeover, files updated to ours ---
TMP_DIR=$(mktemp -d)
echo "0.4.1" > "$TMP_DIR/running_version"
echo "3000"  > "$TMP_DIR/port"
holder_pid=$(spawn_fake_holder "$TMP_DIR/lock" "$TMP_DIR/running_pid")
run_dispatch_subshell "0.4.2" "$TMP_DIR" "$TMP_DIR/out" "$TMP_DIR/err"
result=$?
thtest_begin "dispatch returns 0 on older-running takeover"
assert_equal "0" "$result"
thtest_begin "dispatch prints 'taking over' on older-running"
assert_contains "$(cat "$TMP_DIR/err")" "taking over with v0.4.2"
thtest_begin "running_version is updated to our version after takeover"
assert_equal "0.4.2" "$(cat "$TMP_DIR/running_version")"
sleep 0.1
thtest_begin "old holder is gone after older-running takeover"
if kill -0 "$holder_pid" 2>/dev/null; then
  thtest_fail "holder still alive"
  kill_holder "$holder_pid"
else thtest_pass
fi
rm -rf "$TMP_DIR"

# --- Branch E: legacy (no running_version, no running_pid) → cannot-identify, exit 0 ---
TMP_DIR=$(mktemp -d)
# No running_version, no running_pid. port file present.
echo "3000" > "$TMP_DIR/port"
holder_pid=$(spawn_fake_holder "$TMP_DIR/lock" "$TMP_DIR/running_pid")
rm -f "$TMP_DIR/running_pid"  # explicitly remove (legacy v0.4.1 never wrote it)
run_dispatch_subshell "0.4.2" "$TMP_DIR" "$TMP_DIR/out" "$TMP_DIR/err"
result=$?
thtest_begin "dispatch exits 0 on legacy (no metadata) collision"
assert_equal "0" "$result"
thtest_begin "dispatch prints 'cannot be identified' for legacy"
assert_contains "$(cat "$TMP_DIR/err")" "cannot be identified"
thtest_begin "dispatch does NOT kill holder on legacy"
if kill -0 "$holder_pid" 2>/dev/null; then thtest_pass
else thtest_fail "holder was killed (legacy path should be hands-off)"
fi
thtest_begin "no running_version written by dispatch on legacy"
if [ ! -f "$TMP_DIR/running_version" ]; then thtest_pass
else thtest_fail "running_version was written on legacy"
fi
kill_holder "$holder_pid"
rm -rf "$TMP_DIR"

thtest_summary
