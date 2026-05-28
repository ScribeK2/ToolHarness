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

# appimage_lock_dispatch — version-aware single-instance dispatch.
# Replaces the old `if ! flock -n 9` block in AppRun.tmpl §3.
#
# Requires (caller must set):
#   OUR_VERSION  — our AppImage's version string
#   TH_STATE     — writable state dir
#   LOCK_FILE    — path to the flock file
#   surface_url  — function that opens browser / writes URL file
#
# Side effects:
#   - opens fd 9 on $LOCK_FILE and holds it on success
#   - writes $TH_STATE/running_version and $TH_STATE/running_pid on success
#   - calls `exit 0` on same-version, newer-running, and legacy branches
#   - returns/exits 1 from takeover() on hard failure
appimage_lock_dispatch() {
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    local running_ver port
    running_ver=$(cat "$TH_STATE/running_version" 2>/dev/null || echo "")
    port=$(cat "$TH_STATE/port" 2>/dev/null || echo 3000)

    if [ -z "$running_ver" ]; then
      # Legacy v0.4.1 (or any state without running_version): no metadata,
      # so we can't tell what version is running OR whose PID to signal.
      # Bail with a clear instruction; do not attempt to kill anything.
      echo "ToolHarness: an older version is running but cannot be identified." >&2
      echo "Quit it manually (Ctrl+C, or close its terminal), then re-run this AppImage." >&2
      surface_url "$port"
      exit 0
    elif ver_lt "$running_ver" "$OUR_VERSION"; then
      echo "ToolHarness: v$running_ver is running, taking over with v$OUR_VERSION..." >&2
      takeover || exit 1
    elif [ "$running_ver" = "$OUR_VERSION" ]; then
      echo "ToolHarness v$OUR_VERSION already running on http://localhost:$port"
      surface_url "$port"
      exit 0
    else
      echo "ToolHarness: newer v$running_ver is already running on http://localhost:$port." >&2
      echo "Refusing to downgrade. Run the newer AppImage, or quit it first." >&2
      surface_url "$port"
      exit 0
    fi
  fi
  echo "$OUR_VERSION" > "$TH_STATE/running_version"
  echo "$$"          > "$TH_STATE/running_pid"
}
