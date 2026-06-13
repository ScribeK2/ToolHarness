---
description: Drive a new ToolHarness feature through the full house arc — brainstorm → spec → plan → subagent-TDD → smoke — with scoped, budgeted subagents.
argument-hint: <feature idea, or path to a thoughts/notes file>
---

You are running the ToolHarness feature pipeline for: **$ARGUMENTS**

Follow the house arc, leaning on the `superpowers` skills — do NOT reinvent them.

1. **Brainstorm** — invoke `superpowers:brainstorming`. Explore intent one question
   at a time; propose 2–3 approaches with a recommendation; get my approval.

2. **Spec** — write the design to `.internal/specs/YYYY-MM-DD-<topic>-design.md`.
   This is **gitignored — do NOT commit it** (overrides the skill's default `docs/`
   location). Ask me to review the spec before planning.

3. **Plan** — invoke `superpowers:writing-plans`; save to `.internal/specs/` or
   `.internal/plans/`.

4. **Implement (subagent-TDD)** — invoke `superpowers:subagent-driven-development`.
   For EVERY subagent you dispatch, enforce the anti-runaway contract:
   - **Narrow scope** — name the exact files it may touch; nothing else.
   - **Hard ceiling** — ~80 tool calls. If it blows the budget or wanders, STOP it
     and re-dispatch with tighter scope rather than letting it spiral.
   - **TDD** — failing test first (red), then make it pass (green); per
     `superpowers:test-driven-development`.
   - **Clean-commit contract** — commit only when its tests are green; leave NO
     debug cruft / stray files; report a diff summary before committing.
   - No `Co-Authored-By` trailers.

5. **Verify** — invoke `superpowers:verification-before-completion`. Run `bin/ci`
   and show real output before claiming anything is done.

6. **Smoke** — run programmatic / Playwright smokes yourself; hand off the visual
   smoke to me (our smoke split). Don't claim visual verification you didn't do.

7. When green and smoked, suggest `/release`.

House conventions to honor throughout: brutalist / monospace UI (no rounded/modern,
theme tokens only); input normalizes on submit, never per-keystroke; AppImage
constraint = pure Ruby / HTTP / bundled-static (no host deps).
