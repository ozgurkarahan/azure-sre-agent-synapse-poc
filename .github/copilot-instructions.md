# Copilot Instructions

Read these files for full context:

- `AGENT.md` — Project overview, architecture, environment vars, workflow rules, references
- `PLAN.md` — 5-phase execution plan with cost estimates
- `infra/README.md` — Deploy / verify / teardown commands and known traps

## Copilot-Specific Tips

- Use `@workspace` to give Copilot full project context.
- Pin `AGENT.md` and `PLAN.md` in chat for persistent context.
- Use Copilot Edits (Ctrl+Shift+I) for multi-file changes.
- Run tests / Bicep what-if manually — Copilot CLI cannot execute long-running commands inside your IDE flow.

## End-Session Workflow

See `.github/instructions/end-session.instructions.md`. Summary:

1. Project docs sweep (AGENT.md, .claude/CLAUDE.md Project Context block, PLAN.md status)
2. Git status check
3. Smoke check (project-specific — run tests if any)
4. Summary report
