# Helpers for AppRun's update-takeover dispatch.
# Sourced by AppRun and by tests; defines no globals except the functions below.
# Bash 4+ required ($BASHPID used by callers).

# ver_lt $a $b — true iff $a < $b per version-sort.
# Handles e.g. 0.4.10 > 0.4.2 correctly (sort -V from GNU coreutils).
ver_lt() {
  [ "$1" != "$2" ] && \
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ]
}

# takeover — assume $LOCK_FILE is held by an older AppRun whose PID lives in
# $TH_STATE/running_pid; SIGTERM it, poll for lock release, SIGKILL fallback.
# Requires:
#   - fd 9 already opened on $LOCK_FILE in the caller (via `exec 9>"$LOCK_FILE"`)
#   - $LOCK_FILE, $TH_STATE set
# Honors $APPRUN_SIGTERM_GRACE_SECS (default 8) for the SIGTERM grace period.
# Returns 0 with the lock acquired on success. Returns 1 on hard failure.
takeover() {
  local pid grace_secs max_iter i children
  pid=$(cat "$TH_STATE/running_pid" 2>/dev/null || true)
  if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
    echo "ToolHarness: stale or missing running_pid; lock holder cannot be identified." >&2
    # If the lock-holding process is actually gone, kernel may have released
    # its locks already — try once. Otherwise abort and let the user resolve.
    if flock -n 9; then return 0; fi
    return 1
  fi

  kill -TERM "$pid" 2>/dev/null

  grace_secs=${APPRUN_SIGTERM_GRACE_SECS:-8}
  max_iter=$((grace_secs * 4))
  for ((i=0; i<max_iter; i++)); do
    sleep 0.25
    if flock -n 9; then return 0; fi
  done

  echo "ToolHarness: old server (pid $pid) did not exit within ${grace_secs}s, forcing it." >&2
  # pgrep -P: only direct children. Not process group — that could include
  # the user's interactive terminal or file manager.
  children=$(pgrep -P "$pid" 2>/dev/null || true)
  # shellcheck disable=SC2086  # word-split children intentionally
  kill -KILL "$pid" $children 2>/dev/null

  for i in 1 2 3 4 5 6 7 8; do
    sleep 0.25
    if flock -n 9; then return 0; fi
  done

  echo "ToolHarness: unable to acquire lock after SIGKILL. Something else may be holding it." >&2
  return 1
}
