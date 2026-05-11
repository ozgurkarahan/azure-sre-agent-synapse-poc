# Runbook: Synapse Pipeline Failures

**Pain Points:** #1 (silent failures), #4 (RCA hard without deep log access)

## When to use

Question patterns:
- "Why did pipeline X fail?"
- "What Synapse pipelines failed in the last N hours?"
- "Show me failed pipeline runs in resource group X"
- "Was there a pipeline failure at time T?"

## Primary KQL — Failed pipeline runs with RCA hints

```kql
// Failed and cancelled Synapse pipeline runs, last 24 hours.
// NOTE (2026-05-11): Synapse Analytics writes diagnostic logs to dedicated tables
// (SynapseIntegrationPipelineRuns, etc.) with clean column names — NOT to the
// legacy AzureDiagnostics table with `_s` / `_g` / `_d` suffixes. If you see
// `Status_s` or `RunId_g` in older runbooks, they're for the legacy schema.
let timeRange = 24h;
SynapseIntegrationPipelineRuns
| where TimeGenerated > ago(timeRange)
| where Status in ("Failed", "Cancelled")
| project
    TimeGenerated,
    Pipeline = PipelineName,
    RunId,
    Status,
    Start,
    End,
    DurationMin = round(toreal(datetime_diff('second', End, Start)) / 60.0, 2),
    OperationName,
    SystemParameters
| order by TimeGenerated desc
| take 50
```

## Drill-down — Activity-level failures inside a failed pipeline run

```kql
// Once you've identified a failed pipeline RunId, get the failing activity
let pipelineRunId = "<RunId from previous query>";
SynapseIntegrationActivityRuns
| where PipelineRunId == pipelineRunId
| project
    TimeGenerated,
    Activity = ActivityName,
    ActivityRunId,
    ActivityType,
    Status,
    Start,
    End,
    DurationSec = datetime_diff('second', End, Start),
    OperationName,
    UserProperties
| order by TimeGenerated asc
```

## Pattern 1 — Pipelines that ALWAYS fail at the same activity

```kql
// Find recurring failure modes (same activity, same pipeline, multiple runs)
SynapseIntegrationActivityRuns
| where TimeGenerated > ago(7d)
| where Status == "Failed"
| summarize
    FailureCount = count(),
    FirstSeen = min(TimeGenerated),
    LastSeen = max(TimeGenerated),
    SamplePipelineRunId = take_any(PipelineRunId)
    by PipelineName, ActivityName, ActivityType
| where FailureCount > 1
| order by FailureCount desc
```

## Pattern 2 — Pipelines that succeed but ran much shorter than usual

```kql
// Pipelines that completed unusually fast — possible silent skip
let baseline =
    SynapseIntegrationPipelineRuns
    | where TimeGenerated > ago(30d) and Status == "Succeeded"
    | extend DurationSec = datetime_diff('second', End, Start)
    | summarize medianDurationSec = percentile(DurationSec, 50) by PipelineName;
SynapseIntegrationPipelineRuns
| where TimeGenerated > ago(24h) and Status == "Succeeded"
| extend DurationSec = datetime_diff('second', End, Start)
| join kind=inner baseline on PipelineName
| where DurationSec < medianDurationSec * 0.3
| project TimeGenerated, PipelineName, RunId, DurationSec, medianDurationSec,
    RatioToMedian = round(DurationSec * 1.0 / medianDurationSec, 2)
| order by RatioToMedian asc
```

## Interpretation guidance

| Status | ErrorClass / ErrorCode | Likely cause | Recommended action |
|---|---|---|---|
| `Failed` | `UserError` + `BlobNotFound` | Missing source file (Pipeline E in this pilot) | Check upstream producer; rerun once source is restored |
| `Failed` | `UserError` + `SqlOperationFailed` | SQL syntax / permissions / sink schema issue | Inspect ErrorMessage detail; common = sink table missing column |
| `Failed` | `SystemError` + `SparkApplicationFailed` | Spark notebook crashed (OOM, code error) | Pull Spark application logs from `SynapseBigDataPoolApplicationsEnded` for matching ApplicationName |
| `Failed` | `UserError` + `IntegrationRuntimeNotAvailable` | IR offline or capacity exhausted | Check IR health; may be transient — rerun |
| `Cancelled` | (any) | User-initiated or pipeline-cancellation policy | Check `RunBy` / `TriggerName` to see who/what cancelled |
| `Succeeded` (Pattern 2 anomaly) | n/a | **Silent skip** — pipeline ran but did far less than usual | Cross-check with `synapse-silent-skip-detection.kql.md` runbook |

## Cross-references

- For row-count anomalies on succeeded pipelines → `synapse-silent-skip-detection.kql.md`
- For Spark crashes → `synapse-spark-runaway.kql.md` (covers both runaways AND crashes)
- For pipelines that fired but the alert didn't deliver → `synapse-alert-delivery.kql.md`

## Template context

Pipeline E in this template is intentionally configured to fail with `BlobNotFound` (reads a non-existent file). Use it as the canonical "hard failure" example to demonstrate this runbook end-to-end.
