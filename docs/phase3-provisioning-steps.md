# Phase 3 — Azure SRE Agent provisioning steps (portal walkthrough)

**Why this doc:** The only documented provisioning paths for Azure SRE Agent (as of this template) are (1) the SRE Agent management portal at **`https://sre.azure.com`** (NOT `portal.azuresre.ai` — that's the agent runtime hostname pattern, not the management portal) or (2) Bicep / Terraform templates from `github.com/microsoft/sre-agent` (`sreagent-templates/`). There is no `az` CLI command for `Microsoft.App/agents` create as of `2026-01-01` API version. This document is the click-by-click playbook plus the IaC fallback.

**Estimated time:** 30-45 min including verification.
**Prereq:** Phase 1 deployment is complete (resources from `infra/main.bicep` are up). You can find the deployed resource names with:

```powershell
az deployment sub show --subscription <your-subscription-id> `
  --name '<deployment-name from infra/.deployment-output.json>' `
  --query "properties.outputs" -o json
```

## Step 0 — Critical URL clarification

| URL | What it is | Use it? |
|---|---|---|
| `https://sre.azure.com` | **Management portal — provision + manage agents** | ✅ YES — start here |
| `https://portal.azuresre.ai` | Backend hostname pattern for individual agent endpoints (e.g. `my-agent--abc.def.swedencentral.azuresre.ai`) | ❌ NO — not the management portal; will throw `AADSTS50011` redirect URI mismatch |
| `*.azuresre.ai` | Per-agent runtime + WebSocket | Allow in firewall; don't navigate manually |

**If you see `AADSTS50011: redirect URI 'https://portal.azuresre.ai/auth/callback' does not match' for app `59f0a04a-b322-4310-adc9-39ac41e9631e`** — you went to the wrong URL. Use `sre.azure.com` instead. (The app ID `59f0a04a-b322-4310-adc9-39ac41e9631e` is the public Microsoft Azure SRE Agent first-party app; this is documentation, not a secret.)

## Step 1 — Verify firewall + tenant + provider prerequisites

```powershell
# Network reachability
Test-NetConnection sre.azure.com -Port 443
Test-NetConnection portal.azuresre.ai -Port 443  # for agent runtime later

# Provider check (needs 'agents' resource type)
az provider show -n Microsoft.App --query "{state:registrationState, agentsLocations:resourceTypes[?resourceType=='agents'].locations[0]}" -o json

# Pre-create the SRE Agent first-party SP in your tenant (idempotent; prevents AADSTS issues on first sign-in)
az ad sp create --id 59f0a04a-b322-4310-adc9-39ac41e9631e
```

If `Microsoft.App` provider isn't Registered or doesn't list `agents`, register it: `az provider register --namespace Microsoft.App`.

## Step 2 — Open the management portal

1. Go to **`https://sre.azure.com`** (NOT portal.azuresre.ai)
2. Sign in with `<your-account>@<your-tenant>.onmicrosoft.com`
3. **First-time consent prompt may appear** — click Accept (Owner-at-MG-scope or equivalent role required)
4. If consent UI is blocked, use the admin consent URL:
   ```
   https://login.microsoftonline.com/<your-tenant>.onmicrosoft.com/adminconsent?client_id=59f0a04a-b322-4310-adc9-39ac41e9631e
   ```

## Step 3 — Create the agent

In `sre.azure.com` UI:

| Field | Value | Why |
|---|---|---|
| Subscription | `<your-subscription-id>` | Your sandbox subscription |
| Resource group | `<your-rg>` (default `rg-synapse-sre-pilot`) | Same RG as the Synapse env |
| Region | `Sweden Central` | SRE Agent GA region + matches infra location. *Note: if blocked by tenant policy, try `East US 2` instead* |
| Agent name | `sre-<prefix>-pilot` (e.g., `sre-srepilot-pilot`) | Descriptive |
| Mode | **Reader** | Production-safe; switch to "Operator" later if needed |
| Tags | `SecurityControl=ignore`, `CostControl=ignore`, `project=synapse-sre-pilot`, `env=sandbox` | Tenant-policy bypass + consistency |

Provisioning takes ~3-5 min.

## Fallback — Bicep / Terraform deployment (if the portal is blocked)

`github.com/microsoft/sre-agent` provides `sreagent-templates/` for IaC deployment that bypasses the management portal entirely:

```bash
git clone https://github.com/microsoft/sre-agent.git
cd sre-agent/sreagent-templates

# Login with the data-plane scope
az login --scope "https://azuresre.dev/.default"

./bin/new-agent.sh --recipe azmon-lawappinsights --non-interactive `
  --set agentName=sre-srepilot-pilot `
  --set resourceGroup=<your-rg> `
  --set location=swedencentral `
  --set targetRGs=<your-rg> `
  -o sre-pilot-agent/

./bin/deploy.sh sre-pilot-agent/
```

The ARM resource type is `Microsoft.App/agents`, API version `2026-01-01`. Terraform via `azapi` provider with the same type.

**Cloud Shell is the easiest fallback** — `https://shell.azure.com` has everything pre-installed and bypasses local proxy/firewall:

```bash
# In Cloud Shell:
git clone https://github.com/microsoft/sre-agent.git
cd sre-agent/sreagent-templates
az login --scope "https://azuresre.dev/.default"
./bin/new-agent.sh --recipe azmon-lawappinsights --non-interactive ... -o agent/
./bin/deploy.sh agent/
```

## Step 4 — Capture the agent's MI principal ID

After provisioning completes:

1. Open the new SRE Agent resource
2. **Identity** blade → copy the **System assigned managed identity Object (principal) ID**
3. Save it for the next step

```powershell
# Or via CLI (after provisioning completes):
$agentMI = az resource show `
  --subscription <your-subscription-id> `
  -g <your-rg> `
  --name sre-srepilot-pilot `
  --resource-type "Microsoft.SREAgent/agents" `
  --query identity.principalId -o tsv
echo $agentMI
```

(Resource type name may differ — adjust based on what the portal shows in JSON view.)

## Step 5 — Grant the agent's MI the right roles

The PLAN.md "Hard constraints" require these explicit role assignments. The agent CANNOT query without them:

```powershell
$sub = '<your-subscription-id>'
$rg = '<your-rg>'
$agentMI = '<paste from Step 4>'

# Reader on the RG (browse all resources)
az role assignment create `
  --assignee $agentMI --role 'Reader' `
  --scope "/subscriptions/$sub/resourceGroups/$rg"

# Log Analytics Reader on the LAW (query KQL)
$law = (az monitor log-analytics workspace list -g $rg --query '[0].id' -o tsv)
az role assignment create `
  --assignee $agentMI --role 'Log Analytics Reader' `
  --scope $law

# Monitoring Reader on subscription scope (alert + metric metadata)
az role assignment create `
  --assignee $agentMI --role 'Monitoring Reader' `
  --scope "/subscriptions/$sub"

# Reader on the Synapse workspace (pipeline run details — Reader on RG should cover this, but be explicit)
$synapse = (az synapse workspace list -g $rg --query '[0].id' -o tsv)
az role assignment create `
  --assignee $agentMI --role 'Reader' `
  --scope $synapse

# Synapse Monitoring Operator (data-plane access for pipeline / Spark monitoring API)
az synapse role assignment create `
  --workspace-name (az synapse workspace list -g $rg --query '[0].name' -o tsv) `
  --role 'Synapse Monitoring Operator' `
  --assignee $agentMI

# Verify
az role assignment list --assignee $agentMI --all --query "[].{role:roleDefinitionName, scope:scope}" -o table
```

## Step 6 — Attach scopes to the agent

In the portal, on the SRE Agent resource:

1. **Scope management** blade (or "Resources" tab — wording may vary)
2. **+ Add scope** → select `<your-rg>`
3. Confirm; the agent will index the resources in this RG
4. Wait ~2-3 min for indexing

## Step 7 — Verify the agent can see Synapse

Open the agent's chat UI (in-portal) and submit a low-stakes prompt:

> List the Synapse workspaces you can see and tell me how many Spark pools each has.

Expected: the agent names `synw-<prefix>-<suffix>` and reports `1 Spark pool: pooldefault`.

If the agent says "I don't have access" → recheck Step 5 RBAC. If "no Synapse workspaces found" → recheck Step 6 scope attachment.

## Step 8 — Run the smoke prompts

Open `../demos/transcripts/phase3-smoke-prompts.md` and submit each prompt verbatim. Capture responses. Score using `../demos/transcripts/phase3-rubric.md`.

After all 5 are done, if vanilla score ≥ 12/15 → Phase 3 PASSES. Move to Phase 3.5 (`phase3.5-webhook-wiring-steps.md`).

## Common issues + fixes

| Symptom | Fix |
|---|---|
| Agent UI shows "Could not load" | Firewall — verify `*.azuresre.ai` allowed (Step 1) |
| Agent provisioning fails with `MarketplaceNotEntitled` | Marketplace gate in your tenant — file a support ticket. Probably won't bite (SRE Agent uses Azure-hosted models). |
| Agent says "no log data found" but Synapse pipelines have run | Diagnostic settings on Synapse not flowing to LAW yet. Wait 5-10 min after first pipeline run. Or check: `az monitor diagnostic-settings list --resource <synapse-resource-id>` |
| Agent answers generically ("you have some pipelines") with no IDs | Likely missing `Log Analytics Reader` role. Recheck Step 5. |

## After Phase 3 + 3.5 are complete

- Move to Phase 4 (subagent upload — see `runbooks/README.md`)
