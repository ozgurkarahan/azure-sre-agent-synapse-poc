# Runbook: Synapse Spark Runaway Detection

**Pain Point:** #2 (Spark/SQL clusters never auto-stop — cost + resource leak)

## When to use

Question patterns:
- "Why is Spark cluster X still running?"
- "Show me Spark applications running for more than N hours"
- "What Spark sessions never auto-stopped?"
- "How much Spark compute did I burn yesterday?"

## Primary KQL — Spark applications running > 1 hour

> **NOTE (2026-05-11):** Synapse Spark application logs flow to the dedicated `SynapseBigDataPoolApplicationsEnded` table with column names **without** `_s`/`_d` suffixes. There can be a 10-30 min latency between when a Spark app completes and when its log row appears in LAW. Empty results within the first 30 min after an app finishes are normal — wait and re-query.

```kql
// Spark applications that ran for more than 1 hour
let durationThreshold = 1h;
SynapseBigDataPoolApplicationsEnded
| where TimeGenerated > ago(7d)
| extend Props = parse_json(Properties)
| extend
    SparkPool = tostring(Props.sparkPoolName),
    AppName = tostring(Props.applicationName),
    AppId = tostring(Props.applicationId),
    Submitter = tostring(Props.submitterName),
    StartTime = todatetime(Props.startTime),
    EndTime = todatetime(Props.endTime),
    Status = tostring(Props.applicationStatus),
    NodeCount = toint(Props.nodeCount)
| extend Duration = EndTime - StartTime
| where Duration > durationThreshold
| project TimeGenerated, SparkPool, AppName, AppId, Submitter, StartTime, EndTime, Duration, Status, NodeCount,
    Spent_NodeHours = round(NodeCount * (Duration / 1h), 2)
| order by Duration desc
```

If `SynapseBigDataPoolApplicationsEnded` is genuinely missing (not just latent), check via:

```powershell
az monitor diagnostic-settings list --resource <synapse-workspace-id> --query "[].logs[?categoryGroup=='allLogs' || category=='BigDataPoolApplicationsEnded']"
```

The Bicep in `infra/modules/synapse.bicep` uses `categoryGroup: 'allLogs'` which includes Spark applications.

## Currently-running Spark applications (active sessions)

```kql
// Spark applications that started but haven't ended in the log window
let activeWindow = ago(24h);
let started = SynapseBigDataPoolApplicationsStarted
    | where TimeGenerated > activeWindow
    | extend P = parse_json(Properties)
    | project StartTime = TimeGenerated, AppId = tostring(P.applicationId), SparkPool = tostring(P.sparkPoolName), Submitter = tostring(P.submitterName);
let ended = SynapseBigDataPoolApplicationsEnded
    | where TimeGenerated > activeWindow
    | extend P = parse_json(Properties)
    | project EndTime = TimeGenerated, AppId = tostring(P.applicationId);
started
| join kind=leftanti ended on AppId
| extend RunningFor = now() - StartTime
| order by RunningFor desc
```

## Pool-level cost burn (last 7 days)

```kql
// Total Spark compute burn per pool
SynapseBigDataPoolApplicationsEnded
| where TimeGenerated > ago(7d)
| extend P = parse_json(Properties)
| extend
    SparkPool = tostring(P.sparkPoolName),
    NodeCount = toint(P.nodeCount),
    Duration_h = (todatetime(P.endTime) - todatetime(P.startTime)) / 1h
| summarize
    TotalRuns = count(),
    TotalNodeHours = round(sum(NodeCount * Duration_h), 1),
    LongestRun_h = round(max(Duration_h), 2),
    MedianRun_h = round(percentile(Duration_h, 50), 2)
    by SparkPool
| order by TotalNodeHours desc
```

## Pool config + auto-pause settings (control plane)

```kusto
// Use Resource Graph to see current auto-pause configuration
resources
| where type =~ "microsoft.synapse/workspaces/bigdatapools"
| extend autoPauseEnabled = tobool(properties.autoPause.enabled)
| extend autoPauseDelayMin = toint(properties.autoPause.delayInMinutes)
| extend nodeSize = tostring(properties.nodeSize)
| extend nodeCount = toint(properties.nodeCount)
| project name, resourceGroup, location, autoPauseEnabled, autoPauseDelayMin, nodeSize, nodeCount
```

## Interpretation guidance

| Symptom | Likely cause | Recommended action |
|---|---|---|
| App ran > 12h, status = `Succeeded` | Notebook had `while True` loop or never-ending stream | **[Pain Point #2]** Cancel the app; talk to notebook author. Check `autoPauseDelayMin` is sane. |
| App ran > 12h, status = `Failed` after 12h | Notebook crashed at the auto-pause boundary | Check `Output_s.exception` for OOM / driver loss. Increase pool size OR optimize notebook. |
| App stuck in `Cancelled` for hours | Manual cancel didn't release nodes | Likely a Spark driver issue. Restart the pool: `az synapse spark pool update --enable-auto-pause true` then false then true. |
| `autoPauseEnabled: false` on a non-prod pool | Misconfiguration | **[Pain Point #2]** Always enable auto-pause unless explicit business reason. |
| `autoPauseDelayMin > 240` on dev pool | Misconfiguration | Reduce to 15-30 min for sandbox/dev pools. |
| Pool burns >€20/day in TotalNodeHours | Cost over-run | Audit: who submitted? Are they running prod jobs in dev? Move to prod pool or rightsizing. |

## Template context

Pipeline C in this template runs a Spark notebook with `while True: time.sleep(60)` to demo runaway behaviour. The single Spark pool's auto-pause is temporarily flipped to a longer delay via `az synapse spark pool update` for the demo, then flipped back to 15 min. SRE Agent should detect the unusually-long application and recommend cancelling it + checking auto-pause config.
