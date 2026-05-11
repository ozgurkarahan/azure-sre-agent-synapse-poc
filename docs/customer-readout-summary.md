# Customer Readout — Azure SRE Agent on Synapse Pilot

**Pilot type:** Internal proof of value, sandbox-only
**Score:** **74/75 = 98.7%** across 5 smoke prompts mapped to 4 common Synapse observability pain points
**Recommendation:** Proceed to wire the proactive alert → agent → Teams loop, then propose a joint pilot

---

## Setup (what we built)

A single workspace in `<your-rg>` running real Spark notebooks against real telemetry. The Azure SRE Agent was given **four connectors** during onboarding — and only four:

1. **Log Analytics workspace** — `log-<prefix>-<suffix>` (Synapse pipeline + activity diagnostics)
2. **Application Insights** — `appi-<prefix>-<suffix>` (notebook custom telemetry — intentionally empty to test fallback behavior)
3. **Azure Resources scope** — `<your-rg>` (read on all resources, plus `Synapse Monitoring Operator` after a self-diagnosed RBAC gap on prompt 1)
4. **KQL runbooks as agent knowledge** — the 4 `.kql.md` files originally planned for a custom `synapse_expert` subagent

The fourth item is the architectural finding of the pilot: **attaching runbooks as agent knowledge during onboarding made a separate custom subagent unnecessary**. The vanilla agent + KQL knowledge was equivalent to the planned subagent design.

---

## The score

| Prompt | Pain point | Score |
|---|---|---|
| 1 — General pipeline failure scan | #1 silent failure surfacing | 14/15 |
| 2 — Spark runaway detection | #2 opaque Spark internals | 15/15 |
| 3 — Alert delivery audit | **#3 broken alerting** | **15/15** |
| 4 — Schema drift RCA | **#4 silent data corruption** | **15/15** |
| 5 — Open-ended anomaly hunt | All 4 + bonus | 15/15 |
| **Total** | | **74/75 (98.7%)** |

The single point lost (prompt 1) was for an RBAC gap that the agent **diagnosed itself** and produced the exact `az` CLI command to fix. After RBAC was granted, prompts 2–5 had full data-plane access and scored perfectly.

---

## The killshot — pain point #3, the line that sells the pilot

The Service Health dashboard said the action group was "OK." We had not received a single alert. The agent's diagnosis on prompt 3:

> **"Service Health reports on Azure platform availability, not on whether your action group successfully delivers notifications. An action group with bogus receivers is still a valid Azure resource in a Succeeded provisioning state — it just silently fails at delivery time."**

It then identified both broken receivers — an email going to `bad@invalid.invalid` (an RFC 2606 reserved TLD that will never resolve) and a Logic App webhook with a revoked SAS signature — and produced ready-to-paste `az monitor action-group update` commands to fix each.

This is the gap most Synapse teams have been fighting blind: alerts that look healthy on every dashboard and never reach a human. The agent named it, evidenced it, and remediated it in a single prompt.

---

## The wow factor — pain point #4, when telemetry was empty

`pipeline-B-schema-drift` succeeded. Downstream consumers complained about missing columns. Standard SRE workflow: query LAW for activity errors. Result: nothing. Query App Insights for notebook telemetry. Result: nothing. Most agents would stop there and say "no data."

This agent **downloaded the actual source CSV (`stage/customers-5col.csv`) and the actual output Parquet (`output/customers-4col/*.parquet`) from blob storage and physically diffed the schemas.** It then produced this table:

| Column | Source CSV | Output Parquet |
|---|---|---|
| customer_id | int64 | string (object) — **TYPE DRIFT** |
| name, email, country | string | string |
| **loyalty_tier** | string | **— (DROPPED)** |

Rows: 10 in, 10 out — so row counts can't catch this. Status: Succeeded — so dashboards can't catch this. The agent caught it by **falling back from telemetry to artifacts**, which is exactly the muscle most Synapse SRE teams lack today.

---

## Bonus discoveries (the agent went beyond the script)

We seeded two scenarios for prompt 5: pipeline-A baseline (succeeded), pipeline-B schema drift (succeeded but corrupt). The agent surfaced **two anomalies we had not planned to seed**:

1. **`pipeline-A-baseline` produced no output artifact.** Read-only by design, but the agent flagged it as a silent anomaly worth investigating. True positive.
2. **`customer_id` type drift `int64 → string` on the Parquet write.** A real bug, not a planted one. Would silently break downstream joins.

The agent also wrote, unprompted, a "systemic issues amplifying the risk" section that mapped cleanly onto all 4 pain points. It essentially produced the case for the pilot itself.

---

## Recommendation — next step

**Wire the proactive loop.** What this pilot has now proven: when an SRE asks the right question, the agent gives a concrete, evidenced, remediable answer 98.7% of the time. What it has **not yet** proven: that the agent can fire those answers at an operator at 03:00 without a human prompting for them.

The proactive loop (pre-staged in `docs/phase3.5-webhook-wiring-steps.md`) closes that gap by wiring the existing alert → action group webhook → SRE Agent → Teams channel. Estimated effort: half a day. Once that's live, the conversation moves from "can this work?" to "how do we scale this to N workspaces?"

---

## Cost

Total burn for the entire pilot to date: **~€2–6/day** (Synapse on-demand + LAW ingestion + Spark pool idle). The pilot is cheap to keep running for the duration of any conversation it informs.

---

**Artifacts referenced:**
- Full transcript: `demos/transcripts/phase3-smoke-prompts.md`
- Provisioning steps: `docs/phase3-provisioning-steps.md`
- Proactive loop wiring (next step): `docs/phase3.5-webhook-wiring-steps.md`
- Scoring rubric: `demos/transcripts/phase3-rubric.md`
- Answer key: `demos/transcripts/phase3-answer-key.md`
