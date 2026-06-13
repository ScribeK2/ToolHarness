#!/usr/bin/env bash
# PostToolUse hook: after editing views or asset sources, clobber stale
# precompiled assets so public/assets can never shadow source during smoke
# tests. Fire-and-forget (async); always exits 0.
input="$(cat)"
case "$input" in
  *app/views/*|*app/assets/*|*app/javascript/*)
    cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
    bin/rails assets:clobber >/dev/null 2>&1 || true
    ;;
esac
exit 0
