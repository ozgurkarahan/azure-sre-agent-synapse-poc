---
applyTo: "**"
---

# End Session

When the user says "end session", "wrap up", or "done for today":

1. **Smoke check** — Run any project-specific tests (e.g. Bicep what-if `az deployment sub what-if`, or re-run `phase2-baseline.md` against a fresh sandbox). Confirm the session didn't leave the project broken. If red, decide: fix now, or document as known-broken in `AGENT.md`.

2. **Project docs sweep** — Check whether any of these need updates from today's work:
   - `AGENT.md` (new env vars, changed commands, new "what NOT to do" entries, status changes)
   - `.claude/CLAUDE.md` (Project Context block — bump iteration status)
   - `PLAN.md` (phase status / decisions / open actions)
   - `README.md` (only if quickstart commands or repo layout changed)

3. **Git check** — Run `git status`. If there are uncommitted changes, list them. Verify `.gitignore` still excludes secret files (`.env`, `infra/.synapse-admin-pwd.txt`, etc.).

4. **Summary** — Report:
   - What changed (files touched + reason)
   - What's still TODO
   - Next session pickup point
