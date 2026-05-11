# Phase 2 — Failure injection transcript (reference run, sanitized)

> **Note:** This is a sanitized reference transcript captured from running `run-phase2.ps1` against a live sandbox. Subscription IDs, resource group names, workspace names, storage account names, and pipeline run IDs have been replaced with placeholders. The structural shape (timing, status fields, error types) is preserved so the file remains a useful "what should I expect" reference for someone running Phase 2 against their own deployment.

**Workspace:** `<your-synapse-workspace>` (e.g., `synw-srepilot-<suffix>`)
**Storage:** `<your-storage>` (e.g., `stsrepilot<suffix>`)
**Spark pool:** `pooldefault`

---

## Data staging

```
Alive[################################################################]  100.0000%
Finished[#############################################################]  100.0000%
{
  "client_request_id": "<request-id>",
  "content_md5": "<md5>",
  "date": "<timestamp>",
  "etag": "<etag>",
  "lastModified": "<timestamp>",
  "request_id": "<request-id>",
  "request_server_encrypted": true,
  "version": "<api-version>"
}
```

## Notebooks

### notebook-A-baseline
✅ uploaded
```
{
  "etag": "<etag>",
  "id": "/subscriptions/<your-subscription-id>/resourceGroups/<your-rg>/providers/Microsoft.Synapse/workspaces/<your-synapse-workspace>/notebooks/notebook-A-baseline",
  "name": "notebook-A-baseline",
  "properties": { ... }
```

### notebook-B-schema-drift
✅ uploaded
```
{
  "etag": "<etag>",
  "id": "/subscriptions/<your-subscription-id>/resourceGroups/<your-rg>/providers/Microsoft.Synapse/workspaces/<your-synapse-workspace>/notebooks/notebook-B-schema-drift",
  "name": "notebook-B-schema-drift",
  "properties": { ... }
```

### notebook-C-runaway
✅ uploaded
```
{
  "etag": "<etag>",
  "id": "/subscriptions/<your-subscription-id>/resourceGroups/<your-rg>/providers/Microsoft.Synapse/workspaces/<your-synapse-workspace>/notebooks/notebook-C-runaway",
  "name": "notebook-C-runaway",
  "properties": { ... }
```

### notebook-E-hard-failure
✅ uploaded
```
{
  "etag": "<etag>",
  "id": "/subscriptions/<your-subscription-id>/resourceGroups/<your-rg>/providers/Microsoft.Synapse/workspaces/<your-synapse-workspace>/notebooks/notebook-E-hard-failure",
  "name": "notebook-E-hard-failure",
  "properties": { ... }
```

## Pipelines

### pipeline-A-baseline
✅ created

### pipeline-B-schema-drift
✅ created

### pipeline-C-runaway-spark
✅ created

### pipeline-E-hard-failure
✅ created

## Pipeline runs

### pipeline-A-baseline
```json
{ "runId": "<run-id-A>" }
```

### pipeline-B-schema-drift
```json
{ "runId": "<run-id-B>" }
```

### pipeline-E-hard-failure
```json
{ "runId": "<run-id-E>" }
```

### pipeline-C-runaway-spark
Skipped (re-run with -IncludeRunaway to demo Pain Point #2). Will run until Spark pool auto-pause.

## Run outcomes (poll until terminal status)

### pipeline-A-baseline
- runId: `<run-id-A>`
- final status: **Succeeded** (after ~210s)
- annotations: `synapse-sre-pilot`, `scenario-A`, `baseline`

### pipeline-B-schema-drift
- runId: `<run-id-B>`
- final status: **Succeeded** (after ~120s) — but with schema drift; see Phase 3 prompt 4 for the SRE Agent's RCA
- annotations: `synapse-sre-pilot`, `scenario-B`, `schema-drift`, `pain-point-1`

### pipeline-E-hard-failure
- runId: `<run-id-E>`
- final status: **Failed** (after ~120s)
- annotations: `synapse-sre-pilot`, `scenario-E`, `hard-failure`, `pain-point-4`
- error message excerpt:
  ```
  Operation on target RunHardFailureNotebook failed: AnalysisException
  AnalysisException: [PATH_NOT_FOUND] Path does not exist:
  abfss://stage@<your-storage>.dfs.core.windows.net/this-file-does-not-exist.parquet
  ```

## Summary

- 3 safe pipelines triggered (A, B, E). C was skipped.
- Allow ~10 min for diagnostic logs to land in LAW before querying via SRE Agent.
- Verify with: `az monitor log-analytics query --workspace <law-customer-id> --analytics-query 'SynapseIntegrationActivityRuns | take 10'`
- Phase 3 next: provision SRE Agent (see `../../docs/phase3-provisioning-steps.md`)

## KQL validation — Corrected runbook queries against actual LAW data

**Validation timestamp:** (sanitized)

### Q1 — Pipeline runs (corrected schema)
```kql
SynapseIntegrationPipelineRuns
| where TimeGenerated > ago(1h)
| project TimeGenerated, PipelineName, RunId, Status,
          DurationSec = datetime_diff('second', End, Start), OperationName
| order by TimeGenerated desc
| take 10
```
Expected output shape (one row per pipeline state transition; final terminal row per pipeline shown first):

| DurationSec | OperationName | PipelineName | RunId | Status |
|---|---|---|---|---|
| 472 | pipeline-E-hard-failure - Failed | pipeline-E-hard-failure | `<run-id-E>` | Failed |
| 353 | pipeline-B-schema-drift - Succeeded | pipeline-B-schema-drift | `<run-id-B>` | Succeeded |
| 249 | pipeline-A-baseline - Succeeded | pipeline-A-baseline | `<run-id-A>` | Succeeded |

(Negative DurationSec values appear in `Queued` / `InProgress` rows because End is null at that point — a known KQL quirk; ignore those rows when filtering for terminal status.)

### Q2 — Failed activities
```kql
SynapseIntegrationActivityRuns
| where TimeGenerated > ago(1h) and Status == 'Failed'
| project TimeGenerated, PipelineName, ActivityName, ActivityType, Status, OperationName
| take 10
```

Expected output:

| ActivityName | ActivityType | OperationName | PipelineName | Status |
|---|---|---|---|---|
| RunHardFailureNotebook | SynapseNotebook | RunHardFailureNotebook - Failed | pipeline-E-hard-failure | Failed |

### Q3 — Schema drift custom events (App Insights)
```kql
customEvents
| where TimeGenerated > ago(1h)
| where name in ('SchemaDriftDetected', 'PipelineRowAnomalyDetected')
| take 10
```

Expected on a fresh deployment: **empty result** (the notebook only emits these events if the App Insights connection string is wired). This is intentional — Phase 3 prompt 4 demonstrates how SRE Agent handles "telemetry empty, fall back to artifacts."

### Q4 — Spark applications (may be latent)
```kql
SynapseBigDataPoolApplicationsEnded
| where TimeGenerated > ago(1h)
| take 5
```

Expected: empty for the first 10-30 min after a Spark application completes (latency between Spark job end and log row landing in LAW). Re-query after waiting; the rows will appear.
