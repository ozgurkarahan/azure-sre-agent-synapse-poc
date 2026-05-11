# Claude Code — Project Config

> Read `AGENT.md` for project instructions (auto-loaded via root `CLAUDE.md`).

## Claude-Specific

- Use subagents (`explore`, `task`) for research and verbose long-running work; keep main context for decisions and code edits only.
- When proposing code changes, verify locally (run the test, hit the endpoint, look at the output) before claiming done.
- Update the **Project Context** block below at session end with the active iteration's status — what changed, what's next.

## Project Context

<!-- One paragraph: what this project is, where it came from, key architectural decisions, current iteration status. Update at session end. -->

**Iteration status:** Public template repo for an Azure SRE Agent + Synapse Analytics proof-of-concept. Phase 1 (Bicep deploy: RG + Synapse + Spark pool + LAW + App Insights + Storage + Action Group + alert + sub-level Activity Log diag) and Phase 2 (4 Spark notebooks + 4 wrapper pipelines, 3 runs captured: A/B succeeded, E failed as designed) are complete. Phase 3 (SRE Agent provisioning + smoke prompts), Phase 3.5 (proactive alert→agent→Teams loop) and Phase 4 (`synapse_expert` subagent + 4 KQL runbooks) are fully pre-staged with click-by-click docs in `docs/` since SRE Agent provisioning is portal-only. Key architectural decisions: collapsed to single Spark pool, used notebooks over Copy activities for failure scenarios, captured action group delivery via subscription Activity Log (action groups don't support resource-level diag settings — discovered during deploy). Reference burn: ~€2-6/day. **Next session pickup:** user provisions Azure SRE Agent in portal per `docs/phase3-provisioning-steps.md`, runs 5 smoke prompts, scores via rubric, then wires the proactive loop per `docs/phase3.5-webhook-wiring-steps.md`.
