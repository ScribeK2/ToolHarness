---
description: Cut a ToolHarness release — gated gauntlet (CI → bump → tag → watch AppImage build). Tag-triggered; halts at each gate, never tags on red.
argument-hint: [major|minor|patch]
allowed-tools: Bash(bin/ci), Bash(bin/rails assets:clobber), Bash(git *), Bash(gh *), Read, Edit
---

## Live state
- Current VERSION:   !`cat VERSION`
- Branch:            !`git rev-parse --abbrev-ref HEAD`
- Working tree:      !`git status --short || echo clean`
- Recent tags:       !`git tag --sort=-v:refname | head -3`
- Unpushed commits:  !`git log --oneline @{u}..HEAD 2>/dev/null || echo "(none / no upstream)"`

## Task
Cut a **$1** release (`major`|`minor`|`patch`; default to `patch` if `$1` is empty).
This ships an AppImage via the `v*` tag trigger, so all correctness gates happen
**before** the tag. Move through the gates in order. At each ⛔ STOP, report and wait
for my go-ahead.

1. **Preflight.** Confirm the working tree is clean (or contains only intended
   release changes). If it's dirty with unrelated work, ⛔ STOP and ask.

2. **CI gauntlet.** Run `bin/ci` (rubocop · bundler-audit · importmap audit ·
   brakeman · rails test · system tests · seeds). If anything fails, ⛔ STOP, show
   the failing step's output, and do NOT proceed. Fix or hand back to me first.

3. **Fresh assets.** Run `bin/rails assets:clobber` so no stale precompiled asset
   can shadow source.

4. **Smoke checkpoint.** ⛔ STOP. Tell me CI is green and assets are clobbered.
   I run the visual smoke test locally and reply to continue (our smoke split:
   you do programmatic, I do visual). Do not proceed until I confirm.

5. **Bump.** Compute the next semver from the current `VERSION` per `$1`. Write it
   to the `VERSION` file. Commit as:
   `chore: bump VERSION to X.Y.Z (<one-line summary of what shipped>)`.
   **No `Co-Authored-By` / "Generated with" trailer.**

6. **Push master.** `git push origin master`.

7. **Tag + push.** `git tag vX.Y.Z && git push origin vX.Y.Z` — this triggers the
   AppImage build (`.github/workflows/appimage.yml`).

8. **Watch.** `gh run watch` (or `gh run list` → watch the appimage.yml run) until
   it finishes. Report the final status, the tag, and the run URL. If the build
   fails, ⛔ STOP and report.

Rules: never tag unless gates 1–4 are green; never add commit attribution trailers;
the `VERSION` file is the single source of truth for the version number.
