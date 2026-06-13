---
description: Triage open Dependabot PRs — per-bump test, manual-rebase fallback, then draft a patch release.
allowed-tools: Bash(gh *), Bash(bundle *), Bash(bin/ci), Bash(bin/bundler-audit), Bash(bin/rails test*), Bash(git *), Read
---

## Live state
- Open Dependabot PRs:
!`gh pr list --search "author:app/dependabot state:open" 2>/dev/null || echo "(gh unavailable)"`
- Current VERSION: !`cat VERSION`

## Task
Sweep the open Dependabot PRs above.

1. **Triage** — classify each PR: security (CVE) vs routine; major vs minor/patch.
   Summarize the risk of each. Run `bin/bundler-audit` and surface any hidden CVEs
   not yet covered by an open PR.

2. **Per-bump apply + test** — for each bump you accept, apply it and run `bin/ci`
   (at minimum `bin/bundler-audit` + `bin/rails test`) BEFORE moving to the next.
   Never batch-merge untested bumps.

3. **Rebase fallback** — if `@dependabot rebase` fails ("Oh no!"), bump directly on
   master:
   `bundle lock --update=<gem> --conservative --add-checksums`
   Do NOT use plain `bundle update` — it drops the lockfile CHECKSUMS section locally.

4. **Stale check** — flag any PR dangerously behind master (large commit gap).

5. **Patch release** — once all accepted bumps are green, propose a patch release
   that summarizes each CVE / bump in the commit body, then hand off to
   `/release patch`.

No `Co-Authored-By` trailers.
