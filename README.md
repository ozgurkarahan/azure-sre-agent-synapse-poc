# Azure SRE Agent + Azure Synapse — Proof-of-Concept Pilot Template

A reproducible IaC + runbook + smoke-test scaffold for validating **Azure SRE Agent** against typical **Azure Synapse Analytics** observability pain points: silent pipeline failures, runaway Spark clusters, undelivered alerts, and opaque root-cause analysis. Deploy the sandbox in ~10 minutes, replay 4 designed failure scenarios, and grade SRE Agent's investigations against a documented rubric.

> **Disclaimer.** This is an example template based on a real customer engagement. All customer-specific names, identifiers, subscription IDs, principal IDs, and email addresses have been replaced with generic placeholders. The four "pain points" the template exercises are common across Synapse deployments and are not specific to any one customer.

---

## What the template proves

| # | Pain point | Reproduced by | Captured by |
|---|---|---|---|
| 1 | Pipelines silently skip data with no clear logs | `pipeline-B-schema-drift` (5-col CSV → 4-col Parquet, `loyalty_tier` column dropped) | `SynapseIntegrationActivityRuns` + Spark notebook stdout |
| 2 | Spark clusters never auto-stop (cost + resource leak) | `pipeline-C-runaway-spark` (`while True: time.sleep(60)`) | `SynapseBigDataPoolApplicationsEnded` |
| 3 | Alert emails never delivered despite Service Health "OK" | Action group with `bad@invalid.invalid` (RFC 2606 reserved TLD) + revoked Logic App webhook | Subscription Activity Log → `AzureActivity` |
| 4 | Root-cause analysis is hard without deep log access | `pipeline-E-hard-failure` (reads non-existent file → `AnalysisException`) + cross-cutting RCA across all scenarios | `SynapseIntegrationActivityRuns` + Spark notebook trace |

A bonus 5th scenario — `pipeline-A-baseline` — reads a public NYC Yellow Taxi parquet from Azure Open Datasets as a control / sanity check.

---

## Quickstart

### 1. Deploy the infrastructure (Phase 1)

```powershell
$ErrorActionPreference = 'Stop'
$sub = '<your-subscription-id>'
$loc = 'swedencentral'   # SRE Agent GA region; East US 2 + Australia East also work
$pwd = -join ((48..57) + (65..90) + (97..122) + (33,35,36,37,42,43,45,61,63,64) | Get-Random -Count 24 | ForEach-Object {[char]$_}) + '!Aa9'
Set-Content -Path .\infra\.synapse-admin-pwd.txt -Value $pwd

cd infra
az deployment sub create `
  --subscription $sub --location $loc `
  --name "synapse-sre-pilot-$(Get-Date -Format yyyyMMdd-HHmmss)" `
  --template-file main.bicep `
  --parameters main.parameters.json `
  --parameters synapseSqlAdminPassword=$pwd | Tee-Object -FilePath .\.deployment-output.json
```

Provisions, in a single resource group:

- Synapse Analytics workspace + 1 small Spark pool (15 min auto-pause)
- Data Lake Gen2 storage account (3 file systems: `synapse`, `stage`, `output`)
- Log Analytics workspace + workspace-based Application Insights
- Action Group with two intentionally broken receivers (Pain Point #3 demo)
- Metric alert rule that fires whenever a Synapse pipeline activity ends
- Diagnostic settings: Synapse → LAW (allLogs + AllMetrics) AND subscription Activity Log → LAW (Alert + Administrative + ServiceHealth)
- RBAC: Synapse SystemAssigned MI → `Storage Blob Data Contributor` on the Data Lake

See [`infra/README.md`](infra/README.md) for full deploy / verify / teardown / known-trap detail.

### 2. Inject failure scenarios (Phase 2)

```powershell
.\demos\run-phase2.ps1 -Subscription $sub -ResourceGroup '<your-rg>' -Workspace '<your-synapse-workspace>' -Storage '<your-storage>'
```

Stages the customer CSV, uploads 4 Spark notebooks, creates 4 wrapper pipelines, and runs A / B / E synchronously (C is opt-in via `-IncludeRunaway`). Captures all run IDs and outcomes into [`demos/transcripts/phase2-baseline.md`](demos/transcripts/phase2-baseline.md).

### 3. Provision Azure SRE Agent (Phase 3)

SRE Agent provisioning is portal-only as of writing. Follow the click-by-click playbook in [`docs/phase3-provisioning-steps.md`](docs/phase3-provisioning-steps.md). Attach the resource group as the agent's scope, attach the 4 KQL runbook files as agent **knowledge**, and grant the agent's MI `Reader` + `Log Analytics Reader` + `Monitoring Reader` + `Synapse Monitoring Operator`.

### 4. Run the smoke prompts (Phase 3 acceptance)

Submit each prompt in [`demos/transcripts/phase3-smoke-prompts.md`](demos/transcripts/phase3-smoke-prompts.md) verbatim. Score using the [rubric](demos/transcripts/phase3-rubric.md). Acceptance gate: vanilla average ≥ 12/15. The reference run scored **74/75 (98.7%)** across 5 prompts.

### 5. Wire the proactive loop (Phase 3.5 — optional but recommended)

Follow [`docs/phase3.5-webhook-wiring-steps.md`](docs/phase3.5-webhook-wiring-steps.md) to wire the alert → action group → SRE Agent webhook → Teams flow. This converts vanilla "ask and you receive" SRE Agent into proactive 03:00 triage.

### 6. Teardown

```powershell
az group delete --name '<your-rg>' --yes --no-wait
```

The Bicep is designed to be re-deployable in <10 minutes after a hard teardown.

---

## Repository layout

```
.
├── AGENT.md                              # Project overview for AI assistants (Claude / Copilot CLI)
├── PLAN.md                               # 5-phase execution plan with cost estimates
├── DEMO.md                               # Live presenter guide for showing the validated pilot
├── README.md                             # This file
├── LICENSE                               # MIT
│
├── infra/                                # Phase 1 — Bicep deployment
│   ├── main.bicep                        # Subscription-scoped main template
│   ├── main.parameters.json
│   ├── README.md                         # Deploy / verify / teardown commands + known traps
│   └── modules/
│       ├── storage.bicep                 # Data Lake Gen2 (HNS, MI-only auth)
│       ├── log-analytics.bicep           # LAW + workspace-based App Insights
│       ├── synapse.bicep                 # Workspace + 1 Spark pool + diag settings
│       ├── monitoring.bicep              # Action Group (broken receivers) + alert rule
│       └── rbac.bicep                    # Synapse MI → Storage Blob Data Contributor
│
├── demos/                                # Phase 2 — failure injection
│   ├── README.md                         # Scenario explanations
│   ├── run-phase2.ps1                    # End-to-end stage + upload + run
│   ├── data/
│   │   └── customers-5col.csv            # 10-row sample data (the loyalty_tier source)
│   ├── pipelines/
│   │   ├── notebook-{A,B,C,E}-*.ipynb    # 4 Spark notebooks (1 baseline + 3 failure modes)
│   │   └── pipeline-{A,B,C,E}-*.json     # 4 wrapper pipelines
│   └── transcripts/
│       ├── phase2-baseline.md            # Captured Phase 2 outcomes
│       ├── phase3-smoke-prompts.md       # The 5 prompts + reference responses (sanitized)
│       ├── phase3-answer-key.md          # Ideal answer skeletons (for graders)
│       └── phase3-rubric.md              # 3-axis scoring rubric (specificity / citation / recommendation)
│
├── runbooks/                             # Phase 4 — KQL runbook library
│   ├── README.md
│   ├── synapse_expert.yaml               # Example SRE Agent subagent definition
│   ├── synapse-pipeline-failures.kql.md  # Pain Point #1 + #4
│   ├── synapse-spark-runaway.kql.md      # Pain Point #2
│   ├── synapse-alert-delivery.kql.md     # Pain Point #3 — the killshot runbook
│   └── synapse-silent-skip-detection.kql.md  # Pain Point #1 (sharper)
│
├── docs/
│   ├── customer-readout-summary.md       # 1-page summary memo (the deck content compressed)
│   ├── phase3-provisioning-steps.md      # Click-by-click SRE Agent provisioning
│   └── phase3.5-webhook-wiring-steps.md  # Proactive alert → agent → Teams loop
│
└── slides/                               # (placeholder — readout deck not included)
```

---

## Documented lessons learned

The pilot's most useful findings, captured in the artifacts:

1. **"Service Health reports rule health, not delivery success."** A green Service Health tile on an action group says the alert *rule* is evaluating; it says nothing about whether any receiver actually got the message. Trust `AzureActivity | where OperationName has "Notification"`, not the dashboard tile. See [`runbooks/synapse-alert-delivery.kql.md`](runbooks/synapse-alert-delivery.kql.md).

2. **Action groups don't support resource-level diagnostic settings.** The Azure Monitor API rejects `Microsoft.Insights/diagnosticSettings` on `microsoft.insights/actionGroups` with `ResourceTypeNotSupported`. To capture notification delivery results in LAW, configure a **subscription-scoped** Activity Log diagnostic setting with the `Alert` category enabled. The `infra/main.bicep` template wires this for you.

3. **Schema drift is silent because Synapse evaluates pipeline success on activity exit code, not data quality.** A notebook that drops a column and writes 4-col Parquet from 5-col CSV exits 0 → activity Succeeded → pipeline Succeeded → no alert. The fix is either schema assertions in the notebook, a `sourceColumns != sinkColumns` predicate on a Copy activity, or a downstream contract check. See [`runbooks/synapse-silent-skip-detection.kql.md`](runbooks/synapse-silent-skip-detection.kql.md).

4. **When telemetry is empty, fall back to artifacts.** During the reference run, SRE Agent investigated `pipeline-B-schema-drift` after standard telemetry returned nothing useful: it then **downloaded the actual source CSV and output Parquet from blob storage and physically diffed the schemas**. This is the kind of multi-source detective work that justifies the agent.

5. **The runbook-as-knowledge pattern collapses Phase 3 + Phase 4.** The original plan was vanilla SRE Agent (Phase 3) + custom `synapse_expert` subagent (Phase 4). In practice, attaching the 4 KQL runbook `.md` files as agent knowledge during onboarding gave the vanilla agent the same coverage the subagent would have provided. A separate subagent definition is unnecessary; the YAML in [`runbooks/synapse_expert.yaml`](runbooks/synapse_expert.yaml) is preserved as a template for canvases that prefer the explicit subagent pattern.

See [`docs/customer-readout-summary.md`](docs/customer-readout-summary.md) for the 1-page narrative summary.

---

## Costs

| State | €/day (approximate) |
|---|---|
| Idle (Spark auto-paused, agent stopped) | ~€2 |
| Active testing (Spark 1-2h/day, agent live) | ~€4-6 |
| Worst case (Spark 12h, agent always-on) | ~€11-15 |

Use `az group delete` between sessions for full €0/day. Bicep redeploys in <10 minutes.

---

## Prerequisites

- Azure subscription where you can create Synapse + Log Analytics + Storage resources
- Owner (or Contributor + User Access Administrator) at subscription or management group scope (required for the SRE Agent's MI role assignments)
- Azure CLI 2.x with the Bicep extension
- PowerShell 7+ (the deploy and Phase 2 scripts use PowerShell)
- A region where Azure SRE Agent is GA (Sweden Central, East US 2, or Australia East as of 2026)
- Resource providers registered: `Microsoft.Synapse`, `Microsoft.Storage`, `Microsoft.OperationalInsights`, `Microsoft.Insights`, `Microsoft.AlertsManagement`, `Microsoft.App`

---

## License

[MIT](LICENSE).

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Issues and PRs welcome — particularly additional KQL runbooks for other Synapse failure modes, or ports of the scaffold to Microsoft Fabric / Databricks.

## Security

See [SECURITY.md](SECURITY.md) for how to report vulnerabilities.
