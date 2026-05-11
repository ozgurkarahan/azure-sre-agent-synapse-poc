# Phase 2 — Failure injection scenarios

Per `../PLAN.md` Phase 2. Five scenarios that exercise the four standard Synapse observability pain points + 1 baseline:

| # | Scenario | Pain Point | Expected outcome |
|---|---|---|---|
| A | Baseline (NYC taxi parquet read) | none | SUCCEEDED, ~2M rows read |
| B | Schema drift (5-col CSV → 4-col parquet) | #1 | SUCCEEDED, but `loyalty_tier` silently dropped |
| C | Runaway Spark (`while True: time.sleep(60)`) | #2 | Runs until Spark pool auto-pause kicks in |
| D | Alert never delivered | #3 | Triggered automatically by ANY pipeline activity completing (alert rule fires; broken action group receivers fail to deliver) |
| E | Hard failure (read non-existent file) | #4 | FAILED with AnalysisException |

## Files in this folder

```
demos/
├── data/
│   └── customers-5col.csv             # 10-row sample CSV (5 cols), source for scenario B
├── pipelines/
│   ├── notebook-A-baseline.ipynb      # Spark notebook A
│   ├── notebook-B-schema-drift.ipynb  # Spark notebook B
│   ├── notebook-C-runaway.ipynb       # Spark notebook C
│   ├── notebook-E-hard-failure.ipynb  # Spark notebook E
│   ├── pipeline-A-baseline.json       # Wrapper pipeline A
│   ├── pipeline-B-schema-drift.json   # Wrapper pipeline B
│   ├── pipeline-C-runaway-spark.json  # Wrapper pipeline C
│   └── pipeline-E-hard-failure.json   # Wrapper pipeline E
├── transcripts/
│   ├── phase2-baseline.md             # (created when phase2 runs) — captures outcomes
│   ├── phase3-smoke-prompts.md        # SRE Agent smoke prompts (sanitized reference run)
│   ├── phase3-answer-key.md           # Answer key for grading
│   └── phase3-rubric.md               # Scoring rubric
└── run-phase2.ps1                     # End-to-end deploy + run script
```

## Why notebooks (not Copy activities)

Schema drift scenarios are easier to control with explicit Spark notebooks than with Synapse Copy activities + filter predicates. The simplest cross-scenario approach is **Spark notebooks wrapped by minimal pipelines**:

- ✅ One pattern for all scenarios — easier to reason about + maintain
- ✅ Generates BOTH pipeline-run logs (`SynapseIntegrationActivityRuns`) AND Spark application logs (`SynapseBigDataPoolApplicationsEnded`) → SRE Agent has more surface to query
- ✅ Notebook code is more readable than Copy activity JSON for demoing the bug
- ⚠️ Trade-off: Copy activity outputs include `sourceColumns` / `sinkColumns` natively in `Output_s` JSON. Notebook B works around this by `print()`ing the column counts (visible in Spark stdout) AND optionally emitting an App Insights customEvent.

For production deployments using Copy activities, the same SRE Agent runbooks work — the KQL just queries `Output_s.sourceColumns` directly instead of parsing notebook stdout.

## Run Phase 2

```powershell
cd ..\..\demos
.\run-phase2.ps1 -Subscription <your-subscription-id> -ResourceGroup <your-rg> -Workspace <your-synapse-workspace> -Storage <your-storage>
```

The script:
1. Reads deployment outputs from `..\infra\.deployment-outputs.json` (if present) OR uses the parameter values
2. Uploads `data/customers-5col.csv` to the storage `stage/` container
3. Uploads each `notebook-*.ipynb` to Synapse
4. Creates each `pipeline-*.json` in Synapse
5. Runs A, B, E (synchronously — completes within minutes)
6. Optionally runs C (you'll be prompted — runs forever until Spark auto-pause)
7. Captures all run IDs into `demos/transcripts/phase2-baseline.md`

## Run individual scenarios

```powershell
$rg = '<your-rg>'
$wk = '<your-synapse-workspace>'
az synapse pipeline create-run --workspace-name $wk -g $rg --name 'pipeline-A-baseline'
az synapse pipeline create-run --workspace-name $wk -g $rg --name 'pipeline-B-schema-drift'
az synapse pipeline create-run --workspace-name $wk -g $rg --name 'pipeline-E-hard-failure'

# Pipeline C only when ready to demo runaway scenario:
az synapse spark pool update --workspace-name $wk -g $rg --name pooldefault --enable-auto-pause true --auto-pause-delay-in-minutes 30
az synapse pipeline create-run --workspace-name $wk -g $rg --name 'pipeline-C-runaway-spark'
# After observing runaway behaviour, restore safe auto-pause:
az synapse spark pool update --workspace-name $wk -g $rg --name pooldefault --enable-auto-pause true --auto-pause-delay-in-minutes 15
```

## Verify logs landed in LAW (after pipelines run, allow 5-10 min)

```powershell
$rg = '<your-rg>'
$lawName = (az monitor log-analytics workspace list -g $rg --query '[0].name' -o tsv)
$law = (az monitor log-analytics workspace show -g $rg -n $lawName --query customerId -o tsv)
az monitor log-analytics query --workspace $law --analytics-query "SynapseIntegrationActivityRuns | take 10 | project TimeGenerated, PipelineName_s, ActivityName_s, Status_s"
az monitor log-analytics query --workspace $law --analytics-query "SynapseBigDataPoolApplicationsEnded | take 10 | project TimeGenerated, ApplicationName_s, ApplicationStatus_s"
az monitor log-analytics query --workspace $law --analytics-query "AzureActivity | where OperationName has 'Notification' | take 10"
```

If any of these tables are empty after 10 min:
- `SynapseIntegrationActivityRuns` empty → Synapse diagnostic settings not flowing. Check `az monitor diagnostic-settings list --resource <synapse-resource-id>`
- `SynapseBigDataPoolApplicationsEnded` empty → same diagnostic settings (this category is included)
- `AzureActivity` for Notification empty → sub-level Activity Log diag setting missing OR alert hasn't fired yet OR action group not invoked. Check the alert rule state.
