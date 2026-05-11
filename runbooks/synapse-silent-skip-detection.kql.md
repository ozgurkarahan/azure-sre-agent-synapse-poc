# Runbook: Silent Skip + Schema Drift Detection

**Pain Point:** #1 (Pipelines randomly fail or silently skip data with no clear logs) — sharper version

## When to use

Question patterns:
- "Pipeline X succeeded but the data looks wrong"
- "Did any pipelines silently skip data yesterday?"
- "Detect schema drift in copy activities"
- "Find pipelines with row-count anomalies"

## Primary KQL — Notebook-emitted "0 rows / wrong shape" anomalies

> **NOTE:** This template uses Spark notebooks (not Copy activities) for the failure scenarios. The schema-drift detection therefore requires either (a) parsing notebook stdout in `SynapseBigDataPoolApplicationsEnded.Properties.diagnostics` once Spark logs land, OR (b) querying App Insights `customEvents` if the notebook emitted a `SchemaDriftDetected` event.
>
> For production deployments using Copy activities, the `SynapseIntegrationActivityRuns` rows have a richer body — see Pattern A below.

### Pattern A — Copy activity outputs (production-style data)

```kql
// Succeeded copy activities with row-count or column-count anomalies
SynapseIntegrationActivityRuns
| where TimeGenerated > ago(24h)
| where ActivityType == "Copy"
| where Status == "Succeeded"
| extend UP = parse_json(UserProperties)
| extend SP = parse_json(SystemParameters)
| extend
    rowsRead = toint(UP.rowsRead),
    rowsCopied = toint(UP.rowsCopied),
    rowsSkipped = toint(UP.rowsSkipped),
    sourceColumns = toint(UP.sourceColumns),
    sinkColumns = toint(UP.sinkColumns)
| where rowsCopied == 0
    or (isnotempty(rowsRead) and rowsRead > 0 and rowsCopied < rowsRead)
    or (isnotempty(sourceColumns) and isnotempty(sinkColumns) and sourceColumns != sinkColumns)
| project TimeGenerated, PipelineName, ActivityName, ActivityRunId,
    rowsRead, rowsCopied, rowsSkipped, sourceColumns, sinkColumns,
    Drift = sourceColumns - sinkColumns, UserProperties
| order by TimeGenerated desc
```

### Pattern B — Notebook stdout-based detection (this pilot's scenarios)

```kql
// Find notebook activity runs and check for SCHEMA_DRIFT_DETECTED in stdout
// (requires Spark application log to have landed in LAW — 10-30 min latency)
SynapseIntegrationActivityRuns
| where TimeGenerated > ago(24h)
| where ActivityType == "SynapseNotebook"
| where Status == "Succeeded"
| where PipelineName has "schema-drift"
| join kind=leftouter (
    SynapseBigDataPoolApplicationsEnded
    | where TimeGenerated > ago(24h)
    | extend P = parse_json(Properties)
    | extend AppName = tostring(P.applicationName), Diagnostics = tostring(P.diagnostics)
) on $left.ActivityRunId == $right.AppName
| where Diagnostics has "SCHEMA_DRIFT_DETECTED"
| project TimeGenerated, PipelineName, ActivityName, ActivityRunId, Diagnostics
| order by TimeGenerated desc
```

### Pattern C — App Insights customEvents (most reliable when notebooks instrument)

```kql
// Notebook-emitted custom events for anomaly detection
customEvents
| where TimeGenerated > ago(24h)
| where name in ("SchemaDriftDetected", "PipelineRowAnomalyDetected", "ZeroRowCopy")
| extend
    pipeline = tostring(customDimensions.pipeline),
    sourceColumns = toint(customDimensions.sourceColumns),
    sinkColumns = toint(customDimensions.sinkColumns),
    droppedColumns = tostring(customDimensions.droppedColumns)
| project TimeGenerated, name, pipeline, sourceColumns, sinkColumns, droppedColumns
| order by TimeGenerated desc
```

## Interpretation guidance

| Pattern | Likely cause | Recommended action |
|---|---|---|
| `rowsRead = 0`, `rowsCopied = 0` | Source has no data matching filter — could be expected (off-cycle run) OR a filter that should have matched | Inspect filter predicate. If supposed to match, check upstream source freshness. **[Pain Point #1]** if user expected non-zero. |
| `rowsRead > 0`, `rowsCopied < rowsRead`, `rowsSkipped > 0` | Schema mismatch / type conversion failures, sink rejected rows | **[Pain Point #1]** Pull `typeConversionIssues` from output. Update sink schema OR add type-coercion in copy activity. |
| `sourceColumns != sinkColumns` | **Schema drift** — source has new column(s) not in sink | **[Pain Point #1]** Either: (a) update sink to include new column, (b) add explicit column mapping to ignore extra source columns, (c) page the team that owns the source — they made a breaking change without notice. |
| `warnings` contains "schema" or "column" | Implicit schema drift handled silently | Inspect warnings; same actions as above. |
| `rowsCopied << medianRows` | Volume regression — upstream may be incomplete or filter changed | **[Pain Point #1]** Check upstream completeness; alert downstream consumers BEFORE they consume incomplete data. |
| `customEvents` shows `PipelineRowAnomalyDetected` | Notebook explicitly flagged the anomaly | The notebook KNEW; the alerting layer didn't propagate. Add an alert rule on `customEvents` matching this name. |

## Why this is the SHARPER pain-point #1 story

Original pain point #1 framing: "pipelines silently fail with no clear logs." Customer impression: Synapse is opaque. Reality: the data **is** in the logs (`rowsCopied`, `sourceColumns`, etc.) — but the operator wasn't taught to query for it, and there's no alert wired to row-count regression.

The SRE Agent's value here is **not** "find logs that don't exist" — it's **"surface the silent-skip evidence the operator didn't know to look for"** in the logs that DO exist. Crank this insight up in any demo.

## Template context

Pipeline B in this template is configured with **schema drift**: a 5-column CSV in `stage/` is read by a Spark notebook that explicitly writes only 4 columns to the sink Parquet (the `loyalty_tier` column is dropped). Pipeline B succeeds with `sourceColumns = 5, sinkColumns = 4` and no warning at the activity level. Expected SRE Agent answer:
> Pipeline `pipeline-B-schema-drift` succeeded but copied data with truncated schema. The source CSV (`stage/customers-5col.csv`) has 5 columns; the sink Parquet has 4. The column `loyalty_tier` was silently dropped. **[Pain Point #1]** Recommended actions: (1) Update the notebook to include `loyalty_tier` in the column selection. (2) Add a pipeline pre-check that fails fast on column-count mismatch. (3) Add an alert rule on `SynapseIntegrationActivityRuns` matching `sourceColumns != sinkColumns`.
