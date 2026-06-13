# ToolHarness

Rails 8 app — a single-user, local-first harness of network / DNS / email / SQL
investigation tools for Tier-2 support. Ships as a self-contained **Linux AppImage**
(no host deps). No auth (Devise being removed); prefs are per-browser.

## Commands
- Run the app:      `bin/dev`   — NOT `bin/rails server` alone (jobs won't run; tool runs spin forever)
- Full CI gauntlet: `bin/ci`    — rubocop · bundler-audit · importmap audit · brakeman · rails test · system tests · seeds
- Tests only:       `bin/rails test`  (system: `bin/rails test:system`)
- Lint:             `bin/rubocop`
- Cut a release:    `/release [major|minor|patch]` — releases are **tag-triggered** (`v*` → AppImage build); never hand-roll
- Ship a feature:   `/ship-feature <idea>`
- Dependabot sweep: `/dependabot-sweep`

## Conventions
- **No commit attribution.** Never add `Co-Authored-By` / "Generated with" trailers to commits.
- **Specs & plans live in `.internal/`** (gitignored): `.internal/specs/`, `.internal/plans/`. Do NOT commit them or put them in `docs/`.
- **Smoke split:** Claude runs programmatic / Playwright smokes; the user runs visual smokes (browser auto-open, banner UI). Hand off visual verification — don't claim a feature is visually verified.
- **AppImage constraint:** tools must be pure Ruby / HTTP / bundled-static. No setuid, no `apt install`, no host binaries. See memory `appimage_portability_gotchas` before touching `script/build-appimage.sh` or AppRun.
- **Versioning:** the `VERSION` file at repo root is the source of truth (read at runtime by `update_checker`). Bump it as part of `/release`.

## UI / design
- Brutalist / monospace house style: hard edges, bracketed labels (`[TH]`, `[3]`), theme-token colors. **No rounded corners, shadows, or "modern" styling** unless I explicitly ask.
- New views must work under the theme system (11 themes; see memory `theme_system`) — use theme tokens (`text-fg`, `text-yellow`, …), never hard-coded colors.

## Input handling
- When normalizing domain / URL input (stripping `http://`, etc.), **normalize on submit, never per-keystroke** — per-keystroke handlers have repeatedly blocked typing and broken search.

## Notes
- Durable conventions live in this file; evolving roadmap / status / black-box learnings live in auto-memory (`MEMORY.md`).
- Stale `public/assets` can shadow source during smoke tests — a PostToolUse hook clobbers them after view/asset edits.
