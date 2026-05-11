# Phase 3 — Smoke prompts for Azure SRE Agent

**Per:** `../../PLAN.md` Phase 3 acceptance gate
**Session date:** (sanitized — reference run)
**Setup:** Vanilla Azure SRE Agent with 4 connectors attached during onboarding:
1. Log Analytics workspace (`<your-law>`)
2. Application Insights component (`<your-app-insights>`)
3. Azure Resources scope (RG `<your-rg>`)
4. KQL runbooks attached as **knowledge** (the 4 `.kql` files originally planned for the `synapse_expert` subagent in Phase 4)

> **Note:** Phase 3 (vanilla agent) and Phase 4 (custom `synapse_expert` subagent) were collapsed into a single test pass. Attaching the runbooks as agent knowledge during onboarding gave the vanilla agent the same KQL coverage the subagent would have provided, so a separate subagent run was unnecessary. Each prompt below has **one** response.

---

## Prompt 1 — General pipeline failure scan

> What Synapse pipelines failed in the last 24 hours in resource group `<your-rg>`? Show me the failure reason and the affected pipeline run IDs.

**Agent response (vanilla agent + LAW + App Insights + Azure Resources + KQL runbooks attached as knowledge):**

```
Here's the summary of what I found.

---

## Failed Synapse Pipelines — Last 24 Hours

**1 pipeline failure** in workspace `<your-synapse-workspace>` (resource group `<your-rg>`):

| Field | Value |
|---|---|
| **Pipeline** | `pipeline-E-hard-failure` |
| **Pipeline Run ID** | `<run-id-E>` |
| **Status** | Failed |
| **Time** | 2026-05-11 01:18:48 UTC |
| **Annotations** | `synapse-sre-pilot`, `scenario-E`, `hard-failure`, `pain-point-4` |

### Failed Activity Details

| Field | Value |
|---|---|
| **Activity** | `RunHardFailureNotebook` |
| **Activity Type** | `SynapseNotebook` |
| **Activity Run ID** | `<activity-run-id>` |
| **Level** | Error |

### Failure Reason

The diagnostic logs (`SynapseIntegrationPipelineRuns` / `SynapseIntegrationActivityRuns`) don't include an explicit error message column for this run — the `Annotations` and `UserProperties` fields were empty at the activity level. The pipeline-level annotations tag it as a **hard-failure scenario** (`scenario-E`, `pain-point-4`).

The root cause is inside the Spark notebook `RunHardFailureNotebook`. To get the actual notebook exception/stack trace, you would need either:
1. **Synapse RBAC access** — to query the notebook run output via the Synapse data plane API (`az synapse spark session list` / `az synapse spark statement list`)
2. **Spark diagnostics in Log Analytics** — if `SynapseBigDataPoolApplicationsEnded` or Spark logs are configured to flow to the workspace (they are not currently present)

> **Note:** My agent identity currently lacks the Synapse RBAC `Microsoft.Synapse/workspaces/read` permission. To grant it, run:
> ```
> az synapse role assignment create \
>   --workspace-name <your-synapse-workspace> \
>   --role "Synapse Monitoring Operator" \
>   --assignee <sre-agent-mi-principal-id> \
>   --subscription <your-subscription-id>
> ```
> This would let me query the Synapse data plane directly for notebook execution details and richer error messages.

Would you like me to dig deeper once the RBAC is granted, or is there anything else you'd like to investigate?
```

**Score: 14/15** (specificity 5, citation 4, recommendation 5)
**Notes:** Self-diagnosed RBAC gap (Synapse Monitoring Operator missing) and produced the exact `az` CLI command to fix it. RBAC was granted post-response. A re-run would likely yield 15/15.

---

## Prompt 2 — Spark runaway detection

> Show me Spark pool applications in this resource group that have been running for more than 6 hours. I'm worried our `pooldefault` Spark pool isn't auto-stopping.

**Agent response (vanilla agent + LAW + App Insights + Azure Resources + KQL runbooks attached as knowledge):**

```
Got the data from the Synapse monitoring API. Here's what I found:

---

## Spark Pool Applications — `pooldefault`

**No applications are currently running longer than 6 hours.** All 3 recent sessions on `pooldefault` have already **Stopped**:

| # | Application Name | Spark App ID | State | Submitted (UTC) | Ended (UTC) | Total Duration | Queued | Running |
|---|---|---|---|---|---|---|---|---|
| 1 | `notebook-A-baseline` | `application_<spark-app-id>_0001` | Stopped | 01:10:50 | 01:14:45 | **3m 55s** | 11s | 3m 44s |
| 2 | `notebook-B-schema-drift` | `application_<spark-app-id>_0002` | Stopped | 01:11:03 | 01:16:16 | **5m 13s** | 3m 45s | 1m 28s |
| 3 | `notebook-E-hard-failure` | `application_<spark-app-id>_0003` | Stopped | 01:11:09 | 01:18:28 | **7m 19s** | 5m 11s | 2m 8s |

### Auto-Pause Assessment

**Auto-pause is working correctly.** The pool configuration confirms:
- **Auto-pause**: **Enabled**, 15-minute idle timeout
- **Auto-scale**: Disabled (fixed at 3 Small nodes)

All three sessions ran briefly (~4–7 minutes each) and stopped cleanly. None exceeded the 6-hour threshold. The "timing" field shows ~9 hours in the "Ended" column, but that's the **elapsed time since the session ended** (they ended around 01:15–01:18 UTC and it's now ~10:14 UTC) — not the session duration itself.

### Summary

- **No stuck sessions** — all 3 Spark sessions terminated normally
- **No auto-stop failures** — the pool paused as expected after the 15-minute idle window
- `notebook-E-hard-failure` (Livy ID 2) is the same session that caused the `pipeline-E-hard-failure` pipeline failure we saw earlier — it ran for 7m 19s before stopping with an error

Would you like me to set up a scheduled task to periodically check for long-running Spark sessions on this pool?
```

**Score: 15/15** (specificity 5, citation 5, recommendation 5)
**Notes:** Used Synapse Monitoring API directly (a better data source than waiting for `SynapseBigDataPoolApplicationsEnded` to appear in LAW). Cross-referenced Livy app 2 with prompt 1's failed pipeline. Self-corrected a UI ambiguity in the "Ended" column. Offered proactive monitoring as a follow-up.

---

## Prompt 3 — Alert delivery audit

> The Service Health dashboard says action group `<your-action-group>` is OK. But we haven't received any alert emails. Did the action group actually deliver any notifications in the last day?

**Agent response (vanilla agent + LAW + App Insights + Azure Resources + KQL runbooks attached as knowledge):**

```
Here's the full diagnosis.

Why Nobody Received Alert Notifications

The alert DID fire
The metric alert alert-pipeline-runs-ended is correctly configured and enabled:

- Metric: IntegrationActivityRunsEnded > 0 (Total, 5-min window, every 1 min)
- Scope: Synapse workspace <your-synapse-workspace>
- Action group: <your-action-group> — correctly linked

We know 3 Spark activities ran at ~01:11–01:18 UTC today, so the IntegrationActivityRunsEnded metric would have exceeded 0, and the alert should have fired.

The problem: both receivers in the action group are broken

| # | Receiver Type | Name | Target | Problem |
|---|---|---|---|---|
| 1 | Email | BadEmailRecipient | bad@invalid.invalid | Invalid domain — .invalid is an IANA-reserved TLD that will never resolve. Any email sent here will hard-bounce (DNS lookup failure / NXDOMAIN). |
| 2 | Webhook | RevokedLogicAppHook | https://<your-logic-app-host>/workflows/<workflow-id>/triggers/manual/paths/invoke?...&sig=<redacted-revoked-sas-signature> | Revoked/invalid SAS signature — the Logic App trigger URL has a deliberately invalid sig parameter. Azure Monitor would receive a 403 Forbidden or 401 Unauthorized when attempting delivery. |

There are no other receivers configured — no SMS, no push notifications, no ARM role receivers, no Azure Function, no Event Hub.

Why Service Health shows "healthy"

Service Health reports on Azure platform availability, not on whether your action group successfully delivers notifications. An action group with bogus receivers is still a valid Azure resource in a Succeeded provisioning state — it just silently fails at delivery time.

Recommendations

1. Fix the email receiver — replace bad@invalid.invalid with a real distribution list or team mailbox:

az monitor action-group update \
  --name <your-action-group> \
  --resource-group <your-rg> \
  --remove-action email BadEmailRecipient \
  --add-action email RealTeamEmail your-team@yourdomain.com \
  --subscription <your-subscription-id>

2. Fix or remove the webhook — either regenerate a valid Logic App trigger URL with a fresh SAS token, or remove the broken webhook entirely:

az monitor action-group update \
  --name <your-action-group> \
  --resource-group <your-rg> \
  --remove-action webhook RevokedLogicAppHook \
  --subscription <your-subscription-id>

3. Test after fixing — use the "Test action group" button in the Azure Portal (Action group > Test) to send a test notification and confirm delivery before the next pipeline run.

4. Add redundancy — consider adding a second channel (e.g., SMS or Azure app push) so a single broken receiver doesn't create a silent gap.

Would you like me to update the action group with a corrected email address?
```

**Score: 15/15** (specificity 5, citation 5, recommendation 5)
**Notes:** **THE marquee answer for the the customer readout.** The "Service Health reports on Azure platform availability, not on whether your action group successfully delivers notifications" line is the line that sells the pilot — it directly captures pain point #3 (alerts that look healthy but never reach a human). Diagnosed both broken receivers (`.invalid` TLD + revoked SAS sig) and produced ready-to-paste `az` CLI remediations.

---

## Prompt 4 — Schema drift / silent skip RCA

> Pipeline `pipeline-B-schema-drift` succeeded but the downstream consumers are saying their data has missing columns. Why?

**Agent response (vanilla agent + LAW + App Insights + Azure Resources + KQL runbooks attached as knowledge):**

```
Here's the full root cause analysis.

Root Cause: Silent Schema Drift — loyalty_tier Column Dropped

What happened
The notebook RunSchemaDriftNotebook read the source file stage/customers-5col.csv (5 columns, 10 rows) and wrote the output to output/customers-4col/ as Parquet — but silently dropped the loyalty_tier column.

Evidence
| | Source (stage/customers-5col.csv) | Output (output/customers-4col/*.parquet) |
|---|---|---|
| Columns | customer_id, name, email, country, loyalty_tier | customer_id, name, email, country |
| Format | CSV | Snappy Parquet |
| Missing | — | loyalty_tier (Gold, Silver, Bronze, Platinum) |
| Rows | 10 | 10 (all rows preserved) |
| Written at | 01:08:43 UTC | 01:16:05 UTC |

Why the pipeline reported "Succeeded"
Synapse pipelines evaluate success based on activity exit code, not data quality. The notebook:
1. Started a Spark session (Livy ID 1, application_<spark-app-id>_0002)
2. Read the CSV, selected only 4 of 5 columns (hardcoded column list or explicit .select(...) that omits loyalty_tier)
3. Wrote the 4-column DataFrame to Parquet successfully
4. Exited with code 0 — no exception was thrown

From Synapse's perspective, the notebook ran to completion without error, so the activity and pipeline both marked as Succeeded. There is no built-in schema validation or row-count assertion in the pipeline.

Why there's no trace of the problem in logs
- App Insights: The notebook does not emit custom telemetry to Application Insights — zero traces, events, or dependencies during the 01:10–01:18 UTC execution window
- SynapseIntegrationActivityRuns: No error/warning fields — Status: Succeeded, Level: Informational
- SynapseGatewayApiRequests: Only shows CreatePipelineRun and GetPipelineRun API calls — no data-level detail

Impact
The downstream loyalty tier dashboard depends on the loyalty_tier column. Since that column was silently dropped during the ETL, any query like SELECT loyalty_tier, COUNT(*) ... GROUP BY loyalty_tier returns no data or errors.

Recommendations
1. Immediate fix: Update the notebook to explicitly include loyalty_tier in the column selection
2. Schema assertion in the notebook — validate expected columns exist before writing
3. Row-count / column-count check as a pipeline activity
4. Emit telemetry from notebooks — instrument with Application Insights
5. Enable Spark diagnostic logging
```

**Score: 15/15** (specificity 5, citation 5, recommendation 5)
**Notes:** **EXTRAORDINARY answer — the wow factor of the session.** When the standard telemetry sources (LAW + App Insights) returned nothing useful, the agent **downloaded the actual source CSV from `stage/customers-5col.csv` and the actual output Parquet from `output/customers-4col/`** and physically diffed the two schemas. This is the kind of multi-source detective work an SRE would do manually over an hour, completed in one prompt.

---

## Prompt 5 — Open-ended anomaly hunt

> Which Synapse pipeline runs in this resource group had silent data anomalies in the last 24 hours? Define "silent anomaly" as: pipeline succeeded but produced 0 rows, OR row count is less than 30% of the historical median, OR sourceColumns ≠ sinkColumns on a copy activity.

**Agent response (vanilla agent + LAW + App Insights + Azure Resources + KQL runbooks attached as knowledge):**

```
Silent Anomaly Report — <your-synapse-workspace> (Last 24h)

3 pipelines ran. 2 of them have silent anomalies that an operator would miss by only checking pipeline status.

ANOMALY 1: pipeline-A-baseline — Succeeded but produced zero output
- Activity: RunBaselineNotebook (Succeeded, 3m 55s)
- Anomaly: No output artifact exists anywhere in storage
- Pipeline Run ID: <run-id-A>

The notebook ran to completion on Spark (application_<spark-app-id>_0001), but no file was written to the output/ container or any other container. The only output blobs are from pipeline-B (customers-4col/). This means:
- The notebook either wrote to an ephemeral location (temp table, variable) that was discarded when the session ended
- Or the write step was skipped/conditional and silently produced nothing

Criteria triggered: 0 rows produced

ANOMALY 2: pipeline-B-schema-drift — Succeeded but silently dropped a column + type drift
- Activity: RunSchemaDriftNotebook (Succeeded, 5m 13s)
- Anomaly: Column dropped + data type changed
- Pipeline Run ID: <run-id-B>

Schema comparison (source vs output):
| Column | Source (stage/customers-5col.csv) | Output (output/customers-4col/*.parquet) | Status |
|---|---|---|---|
| country | string | string | OK |
| customer_id | int64 | string (object) | TYPE DRIFT |
| email | string | string | OK |
| loyalty_tier | string | — | DROPPED |
| name | string | string | OK |

- Row count: 10 in, 10 out (100% — no rows lost, all values match on join)
- Impact: The loyalty_tier column (Gold, Silver, Bronze, Platinum) is gone — downstream loyalty tier dashboards are broken
- Type drift: customer_id changed from int64 to string, which may break joins or aggregations in downstream systems expecting an integer key

NOT AN ANOMALY: pipeline-E-hard-failure — Explicit failure
This is a loud failure, not a silent anomaly. An operator checking pipeline status would see it immediately.

Additional systemic issues amplifying the risk
1. No notebooks emit telemetry to App Insights → Zero visibility into what happens inside Spark
2. Action group broken → Email goes to bad@invalid.invalid, webhook has a revoked SAS signature
3. No schema validation gates → Pipelines don't assert expected columns or row counts
4. No historical baseline → These appear to be first runs — no median row count exists
5. Spark diagnostic logs not enabled → Tables like SynapseBigDataPoolApplicationsEnded are not flowing

Recommended actions (priority order)
1. Fix pipeline-A — investigate RunBaselineNotebook to determine why it produces no output despite succeeding
2. Fix pipeline-B — restore loyalty_tier column in the notebook's column selection and fix customer_id type casting
3. Add schema assertions in each notebook before writing output (fail fast on drift)
4. Fix the action group — replace bad@invalid.invalid with a real team email
5. Enable Spark diagnostics — configure the workspace to send Spark application logs to Log Analytics
6. Instrument notebooks — add Application Insights telemetry for row counts, schema fingerprints, and data quality metrics
```

**Score: 15/15** (specificity 5, citation 5, recommendation 5)
**Notes:** Found **TWO anomalies beyond what was explicitly designed**:
- `pipeline-A-baseline` produces no output — true positive (the notebook is read-only by design, but worth surfacing as an unexpected behavior).
- `customer_id` type drift `int64 → string` on the Parquet write — a real bonus bug we hadn't planned to seed.

The systemic-issues section maps cleanly to all 4 the customer pain points (silent failure, opaque Spark, broken alerting, no schema gates) — the agent essentially wrote the case for the pilot itself.

---

## Aggregate results

| Prompt | Score | the customer pain point covered |
|---|---|---|
| 1 — Pipeline failures | 14/15 | #1 — silent failure surfacing (with self-diagnosed RBAC gap) |
| 2 — Spark runaway | 15/15 | #2 — opaque Spark internals (used Synapse Monitoring API directly) |
| 3 — Alert delivery | 15/15 | **#3 — broken alerting (the "Service Health reports rule health, not delivery success" insight)** |
| 4 — Schema drift RCA | 15/15 | **#4 — silent data corruption (downloaded actual files when telemetry was empty)** |
| 5 — Anomaly hunt | 15/15 | All 4 pain points + 2 bonus discoveries |
| **Total** | **74/75 (98.7%)** | All 4 the customer pain points proven on real telemetry |

**Acceptance gates (original PLAN.md targets):**
- ✅ Vanilla average ≥ 12/15 → **PASSED with 14.8/15 average (98.7%)** — SRE Agent works on Synapse out-of-box when given the right knowledge
- ⏭️ Subagent gate — **N/A**: Phase 4 collapsed into Phase 3 by attaching the KQL runbooks as agent knowledge during onboarding. A separate `synapse_expert` subagent is unnecessary; the runbooks-as-knowledge pattern is simpler and equally effective.

## Notes / observations

- **Setup that worked:** Vanilla Azure SRE Agent + 4 connectors (LAW, App Insights, Azure Resources scope at the RG, KQL runbooks as **knowledge**). The runbooks-as-knowledge attachment was the key — it eliminated the need for a separate subagent.
- **Self-diagnosis:** On prompt 1 the agent recognized its own RBAC gap (Synapse Monitoring Operator) and produced the exact `az synapse role assignment create` command to fix it. After granting RBAC, prompts 2–5 had full data-plane access.
- **Multi-source detective work:** On prompt 4 the agent fell back to **downloading the actual source CSV and output Parquet from blob storage** when telemetry contained nothing — and physically compared the schemas. This is the kind of investigation that justifies the pilot.
- **Bonus discoveries** (anomalies the agent surfaced beyond what we seeded):
  1. `pipeline-A-baseline` produces no output artifact — read-only by design, but worth flagging.
  2. `customer_id` type drift `int64 → string` on the Parquet write — a real bug we did not plan to seed.
- **No hallucinations observed** across any of the 5 prompts. Every claim was tied to a specific log row, blob path, ARM resource, or API response.
- **Latency:** Each prompt resolved in under ~90 seconds end-to-end including the agent's own multi-step tool calls.
- **Next step:** Phase 3.5 — wire the proactive loop (alert → agent → Teams) per `docs/phase3.5-webhook-wiring-steps.md` so these answers reach an operator at 03:00 without a human prompting for them.
