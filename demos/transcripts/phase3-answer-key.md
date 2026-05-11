# Phase 3 — Answer key (DO NOT show to the agent)

**Per:** `../../PLAN.md` Phase 3 correctness rubric
**Usage:** Use this file ONLY to grade the agent's responses. Do not paste any of this into the agent prompts.

For each smoke prompt below, the "ideal answer" is what a senior Synapse SRE would write after 5 minutes of investigation. Use it as the benchmark for the rubric in `phase3-rubric.md`.

---

## Answer 1 — Pipeline failures (last 24h)

**Ideal answer skeleton:**

> In `<your-rg>` over the last 24 hours, **N pipelines failed** in workspace `<your-synapse-workspace>`:
>
> | Time | Pipeline | RunId | Status | Reason |
> |---|---|---|---|---|
> | YYYY-MM-DD HH:MM | pipeline-E-hard-failure | <run-id> | Failed | UserError + BlobNotFound: `stage/missing-source.parquet` does not exist |
> | (etc.) |
>
> **Evidence:** I queried `SynapseIntegrationPipelineRuns` filtered to `Status in ("Failed", "Cancelled")` and `TimeGenerated > ago(24h)`. Activity-level error details came from `SynapseIntegrationActivityRuns` joined on `PipelineRunId_g`.
>
> **Recommended action for `pipeline-E-hard-failure`:** Confirm the source file is actually missing (it should be — this is a sandbox demo of pain point #4). In production, this would mean the upstream producer didn't deliver; alert the upstream team or wire a `BlobCreated` Event Grid trigger to gate this pipeline.

**Required citations:**
- Table: `SynapseIntegrationPipelineRuns`
- At least one specific RunId from the actual log
- Error code AND error message excerpt

**Required recommendation:** Either rerun-when-source-restored, or wire a pre-check, or alert upstream — anything actionable.

---

## Answer 2 — Spark runaway

**Ideal answer skeleton:**

> Spark pool `pooldefault` in workspace `<your-synapse-workspace>` has **N applications** that ran for more than 6 hours in the last 7 days.
>
> | Application | StartTime | Duration | Status | Submitter |
> |---|---|---|---|---|
> | <app-name> | YYYY-MM-DD HH:MM | 12h 03m | Succeeded | <upn> |
>
> The longest-running app (`<app-name>`) was submitted by `<upn>` and ran a notebook with what appears to be an infinite loop (`while True: time.sleep(60)`). It only stopped because auto-pause finally triggered after 12h.
>
> **Evidence:** I queried `SynapseBigDataPoolApplicationsEnded` filtered on `Duration > 6h`. The notebook's body was inferred from the `Notes_s` column / Spark History Server URL.
>
> **Pain Point #2 confirmed.** Recommended actions:
> 1. Cancel the application via Synapse Studio Spark Monitor (already auto-paused, so no immediate cost).
> 2. Update auto-pause to 30 min on `pooldefault` (currently 15 min after the demo, but was temporarily set to 12h for this scenario).
> 3. Add a metric alert on `BigDataPoolApplicationsActive > 0 for 4h` to catch this earlier in production.

**Required citations:**
- Table: `SynapseBigDataPoolApplicationsEnded`
- Specific application ID + duration

**Required recommendation:** Cancel + auto-pause config + alert recommendation.

---

## Answer 3 — Alert delivery (THE killshot question for the customer)

**Ideal answer skeleton:**

> Action group `<your-action-group>` was invoked **N times** in the last 24 hours. **Zero notifications successfully delivered.**
>
> | Channel | Recipient | Attempts | Succeeded | Failed |
> |---|---|---|---|---|
> | Email | bad@invalid.invalid | N | 0 | N |
> | WebHook | RevokedLogicAppHook | N | 0 | N |
>
> **Failure detail:**
> - Email delivery: SMTP bounce (recipient mailbox does not exist; ErrorReason: `552 5.2.1 Mailbox unavailable`)
> - Webhook delivery: HTTP 403 (revoked SAS signature; ErrorReason: `InvalidSignature`)
>
> **Evidence:** I queried `ActionGroupOperations` filtered on `DeliveryStatus != "Succeeded"`. Webhook detail came from `ActionGroupSecondaryActions` filtered on `HttpStatusCode_s !startswith "2"`.
>
> **The Service Health dashboard reads "OK" because it reports on the alert RULE health, NOT the delivery success.** This is the [Pain Point #3] core insight: a green tile in Service Health does NOT mean your team got notified. Trust `ActionGroupOperations`, not the dashboard tile.
>
> **Recommended actions:**
> 1. Replace the bad email recipient with a real distribution list.
> 2. Rotate the Logic App SAS signature and update the action group webhook URL.
> 3. Add a third channel (Teams via the SRE Agent webhook — see Phase 3.5 wiring) so future alerts have a working delivery path even if SMTP/Logic App breaks again.

**Required citations:**
- Tables: `ActionGroupOperations` AND `ActionGroupSecondaryActions`
- Specific count of failed attempts
- Specific error reason for each channel

**Required recommendation:** Three concrete actions including the "OK ≠ delivered" insight callout.

---

## Answer 4 — Schema drift RCA

**Ideal answer skeleton:**

> Pipeline `pipeline-B-schema-drift` succeeded but its Copy activity had a schema mismatch:
>
> - Source: `stage/customers.csv` — **5 columns** (`customer_id`, `name`, `email`, `country`, `loyalty_tier`)
> - Sink: Delta table `output/customers` — **4 columns** (`customer_id`, `name`, `email`, `country`)
>
> The new column `loyalty_tier` was silently dropped during the copy. The activity reports `rowsRead = N`, `rowsCopied = N` (both equal — no row drop), but `sourceColumns = 5`, `sinkColumns = 4` — only the column count differs.
>
> **Evidence:** I queried `SynapseIntegrationActivityRuns` for the latest succeeded copy activity in `pipeline-B-schema-drift`, then parsed the `Output_s` JSON for `sourceColumns`, `sinkColumns`, `sourceColumnNames`, `sinkColumnNames`. The mismatch is in the `loyalty_tier` field.
>
> **Pain Point #1 confirmed.** Recommended actions:
> 1. Update the sink Delta table schema to add the `loyalty_tier` column.
> 2. Add a pipeline pre-check (Lookup activity + If Condition) that fails fast on `sourceColumns != sinkColumns`.
> 3. Add a metric/log alert on `SynapseIntegrationActivityRuns` matching this mismatch pattern.
> 4. Long-term: enforce a contract via Schema Registry or Great Expectations / Soda Core data-quality checks at the boundary.

**Required citations:**
- Table: `SynapseIntegrationActivityRuns`
- Specific activity name + RunId
- Source column count vs sink column count

**Required recommendation:** Sink schema update + pre-check + alert + long-term contract enforcement.

---

## Answer 5 — Anomaly hunt

**Ideal answer skeleton:**

> In the last 24 hours in `<your-rg>`, I found **N silent anomalies** matching at least one of your three criteria:
>
> | Pipeline | Activity | RunId | Anomaly type | Detail |
> |---|---|---|---|---|
> | pipeline-B-schema-drift | CopyCustomers | <run-id> | sourceColumns ≠ sinkColumns | 5 vs 4 (loyalty_tier dropped) |
> | (any other anomalies present) |
>
> **Evidence:** I queried `SynapseIntegrationActivityRuns` filtered on `ActivityType_s == "Copy"`, parsed the `Output_s` JSON, and applied three filters in parallel:
> - `rowsCopied == 0` → silent skip
> - `rowsCopied < p25Rows * 0.5` (joined against a 30d baseline) → row-count regression
> - `sourceColumns != sinkColumns` → schema drift
>
> The 30d baseline came from the same table grouped by `(PipelineName_s, ActivityName_s)` with `percentile(rowsCopied, 25)`.
>
> **Pain Point #1 confirmed at scale.** Recommended actions:
> 1. For each anomaly above, follow the per-pipeline runbook in `runbooks/synapse-silent-skip-detection.kql.md`.
> 2. Promote this query to a saved Log Analytics query + scheduled alert that fires daily if any new anomalies appear.
> 3. Add a Workbook visual showing anomaly count per day per pipeline so trends are visible to operators.

**Required citations:**
- Table: `SynapseIntegrationActivityRuns`
- All three filter clauses present in the KQL
- At least one specific anomaly with concrete fields

**Required recommendation:** Per-anomaly investigation + saved query + workbook.

---

## Pain-point coverage matrix

| Pain point | Ideal answer covers it? |
|---|---|
| #1 (silent failures) | Answers 4 + 5 |
| #2 (clusters never auto-stop) | Answer 2 |
| #3 (alerts never delivered) | Answer 3 — this is the marquee one |
| #4 (RCA without deep log access) | Answers 1 + 4 + 5 (cross-cutting) |

If the agent (vanilla or subagent) covers all 4 pain points across the 5 answers with specific evidence and actionable recommendations → **the SRE Agent value prop for the customer is proven**.
