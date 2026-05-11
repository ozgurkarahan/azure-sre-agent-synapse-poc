# Synapse + Azure SRE Agent — Pilot Template

## Overview

A reproducible IaC + runbook + smoke-test scaffold for validating that **Azure SRE Agent** can investigate four common Synapse Analytics observability pain points. The repo is the sanitized public template based on a real customer engagement; all customer-specific identifiers have been replaced with placeholders.

The four pain points the template reproduces and exercises:

1. Pipelines randomly fail or silently skip data with no clear logs
2. Spark / SQL clusters sometimes never auto-stop (cost + resource leak)
3. Alert emails never delivered despite the Service Health dashboard reporting "OK"
4. Root-cause analysis is hard without deep log access

## Engagement details

| Field | Value |
|---|---|
| **Topic** | Azure SRE Agent on Synapse — pilot validation template |
| **Format** | Bicep IaC + 4 failure-mode pipelines + KQL runbook library + agent prompt set |
| **Subscription** | `<your-subscription-id>` (set in `infra/main.parameters.json` and the deploy script) |
| **Region** | Sweden Central (SRE Agent GA region; East US 2 + Australia East also work) |
| **Resource group** | `<your-rg>` (single RG, easy teardown) |

## Deliverables (all present in this repo)

- [x] **Bicep template** in `infra/` provisioning Synapse + LAW + App Insights + Storage + Action Group + alert + diagnostic settings
- [x] **4 failure-mode Spark notebooks + wrapper pipelines** in `demos/pipelines/`
- [x] **`synapse_expert` SRE Agent subagent YAML** + KQL runbook library in `runbooks/`
- [x] **Smoke-test prompt set** + answer key + scoring rubric in `demos/transcripts/`
- [x] **Cost analysis + teardown protocol** in `infra/README.md`
- [x] **Customer-readout summary memo** in `docs/customer-readout-summary.md`
- [x] **Live presenter guide** in `DEMO.md`

## Reference Documents

| Document | Contents |
|---|---|
| `PLAN.md` | The 5-phase execution plan (provisioning → failure injection → SRE Agent → custom subagent → readout) |
| `README.md` | Public-facing overview, quickstart, repository layout |
| `infra/README.md` | Bicep deploy / verify / teardown commands + known traps |
| `runbooks/README.md` | KQL runbook index + subagent YAML usage |
| `demos/README.md` | Phase 2 failure-injection scenario explanations |
| `docs/customer-readout-summary.md` | 1-page narrative summary of pilot results |

## First Session Instructions

When an AI assistant is launched in this project for the first time:

1. **Read `PLAN.md`** end-to-end — it has the 5 phases, cost estimates, and Bicep skeleton plan
2. **Read `infra/README.md`** for deploy / teardown commands and known traps (publicNetworkAccess flips, MI auth requirements)
3. **Verify Az CLI is logged in** to the target subscription (`az account show`)
4. **Verify Bicep extension** (`az bicep version`)
5. **Enter plan mode** before writing any new Bicep — propose resource topology, policy mitigations, cost estimate, then wait for user approval
6. **STOP and confirm with user** before any spend > €10/day

## Workflow Rules

1. **Plan before provisioning** — every Bicep deploy needs a written plan with cost estimate
2. **Always teardown when idle** — `az group delete --name <your-rg> --yes` between sessions if not actively running tests; the spend clock is real
3. **Verify before done** — every "this works" claim needs an actual command + output captured under `demos/transcripts/`
4. **No blind retries** — if SRE Agent fails to answer something, diagnose root cause (RBAC? data not in LA? KQL gap?) before adjusting subagent runbook
5. **Capture every test run** — every prompt + response from SRE Agent goes under `demos/transcripts/<date>-<scenario>.md`

## Platform & Environment

- Windows 11 / macOS / Linux + PowerShell 7+
- Azure CLI 2.x with Bicep extension
- Optional: `azd` (Azure Developer CLI)
- Python 3.11+ (only required for any helper scripts)
- Target subscription must allow: Synapse workspace creation, Log Analytics workspace creation, Storage account creation with HNS enabled, Action Group creation
- If your tenant enforces "managed identity-only auth" or "no public network access" policies, see `infra/README.md` for the tag-bypass and re-enable-public-access workarounds

## What NOT To Do

- Do not spin up a dedicated SQL pool unless you genuinely need it (the single Spark pool is enough for pain points #1-2 and €€€ saved)
- Do not commit any `.env` file or any file matching `*-pwd.txt`, `*.pem`, `*.key` — `.gitignore` already covers these
- Do not leave the Spark pool without auto-stop set in the Bicep — defeats the entire pain-point #2 demo if the demo cluster also forgets to stop
- Do not skip the diagnostic-settings step — without Synapse logs in LAW, SRE Agent has nothing to chew on
- Do not push real customer data into the sandbox — synthetic data only (the `customers-5col.csv` shipped in `demos/data/` is intentionally synthetic)
