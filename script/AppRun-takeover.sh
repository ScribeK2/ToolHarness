# Helpers for AppRun's update-takeover dispatch.
# Sourced by AppRun and by tests; defines no globals except the functions below.
# Bash 4+ required ($BASHPID used by callers).

# ver_lt $a $b — true iff $a < $b per version-sort.
# Handles e.g. 0.4.10 > 0.4.2 correctly (sort -V from GNU coreutils).
ver_lt() {
  [ "$1" != "$2" ] && \
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ]
}
