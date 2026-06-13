#!/usr/bin/env bash
# Stop hook: non-blocking reminder. Only fires when there are local commits not
# yet on the upstream — i.e. you're about to push/release — nudging a CI run
# first. Stays quiet during normal mid-feature work. Always exits 0.
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
ahead="$(git rev-list --count @{u}..HEAD 2>/dev/null || echo 0)"
if [ "${ahead:-0}" -gt 0 ]; then
  echo "Reminder: ${ahead} unpushed commit(s). Run bin/ci (or /release) before pushing."
fi
exit 0
