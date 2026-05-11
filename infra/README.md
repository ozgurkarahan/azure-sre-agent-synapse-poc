# `infra/` — Phase 1 Bicep deployment

Deploys the Synapse + Log Analytics + Storage + Action Group footprint for the Synapse + SRE Agent pilot template (Phase 1 of the 5-phase plan in `../PLAN.md`).

## What gets deployed

| Resource | Name pattern | Purpose |
|---|---|---|
| Resource group | `<your-rg>` (default `rg-synapse-sre-pilot`) | Single RG, easy teardown. Tagged `SecurityControl=ignore` + `CostControl=ignore` (only relevant if your tenant has policies that strip these settings; harmless otherwise). |
| Storage account | `st<prefix><suffix>` | Data Lake Gen2 (HNS on); managed-identity-only auth, no shared keys. Three filesystems: `synapse` (default), `stage` (raw inputs), `output` (pipeline writes). |
| Log Analytics | `log-<prefix>-<suffix>` | PerGB2018, 30-day retention. Target for Synapse + Action Group diagnostic settings. |
| App Insights | `appi-<prefix>-<suffix>` | Workspace-based, backed by the LAW above. For Spark notebook custom events. |
| Synapse workspace | `synw-<prefix>-<suffix>` | SystemAssigned MI; default storage = the Data Lake; firewall AllowAllWindowsAzureIps. |
| Spark pool | `pooldefault` | Single pool, Small / 3 nodes / 15 min auto-pause. Pipeline C flips auto-pause to a longer delay temporarily. |
| Action Group | `ag-<prefix>-<suffix>` | Two deliberately-broken receivers (bad email + revoked Logic App webhook) for pain point #3 demo. SRE Agent webhook added in Phase 3.5. |
| Alert rule | `alert-pipeline-runs-ended` | Fires whenever a pipeline activity completes — exercises the broken delivery path. |
| Diagnostic settings | (2 of them) | Synapse → LAW (allLogs + AllMetrics) AND subscription Activity Log → LAW (Alert + Administrative + ServiceHealth + Autoscale categories). The subscription-scoped one is **critical** — without it, SRE Agent cannot see SMTP/webhook delivery evidence (action groups don't support resource-level diag settings). |

## Cost estimate

| State | €/day |
|---|---|
| Idle (Spark auto-paused) | ~€2 |
| Active testing (Spark running 1-2h/day) | ~€4-6 |
| Worst case (Spark running 12h, no auto-pause flip) | ~€11 |
| Soft ceiling | €60 |

## Prerequisites

- Az CLI logged into your target subscription (`az account set --subscription <your-subscription-id>`)
- Owner or Contributor + User Access Administrator at sub or MG scope
- Resource providers registered: `Microsoft.Synapse`, `Microsoft.AlertsManagement`, `Microsoft.Storage`, `Microsoft.OperationalInsights`, `Microsoft.Insights`

## Deploy

```powershell
$ErrorActionPreference = 'Stop'
$sub = '<your-subscription-id>'
$loc = 'swedencentral'
$pwd = -join ((48..57) + (65..90) + (97..122) + (33,35,36,37,42,43,45,61,63,64) | Get-Random -Count 24 | ForEach-Object {[char]$_}) + '!Aa9'
Set-Content -Path .\.synapse-admin-pwd.txt -Value $pwd

# Dry run first
az deployment sub create `
  --subscription $sub `
  --location $loc `
  --template-file main.bicep `
  --parameters main.parameters.json `
  --parameters synapseSqlAdminPassword=$pwd `
  --what-if

# Real deploy
az deployment sub create `
  --subscription $sub `
  --location $loc `
  --name "synapse-sre-pilot-$(Get-Date -Format yyyyMMdd-HHmmss)" `
  --template-file main.bicep `
  --parameters main.parameters.json `
  --parameters synapseSqlAdminPassword=$pwd | Tee-Object -FilePath .\.deployment-output.json
```

The Synapse SQL admin password is stored in `infra/.synapse-admin-pwd.txt` (gitignored). It is generated fresh per deployment.

## Verify

```powershell
$rg = '<your-rg>'

# Group exists
az group show -n $rg --subscription $sub -o table

# All resources present
az resource list -g $rg --subscription $sub --query "[].{name:name, type:type}" -o table

# Synapse Studio URL
az deployment sub show --subscription $sub --name '<deployment-name>' --query "properties.outputs.synapseStudioUrl.value" -o tsv

# Check that diagnostic settings are populating LAW (wait ~5 min after first pipeline run)
$lawName = (az monitor log-analytics workspace list -g $rg --query '[0].name' -o tsv)
az monitor log-analytics query `
  --workspace (az monitor log-analytics workspace show -g $rg -n $lawName --query customerId -o tsv) `
  --analytics-query "SynapseIntegrationPipelineRuns | take 5"
```

## Redeploy after policy tag stripping

If Storage or Synapse connectivity breaks unexpectedly, your tenant's policies may have stripped the `SecurityControl`/`CostControl` tags and re-enforced `publicNetworkAccess: Disabled`.

Quick fix (re-tag + re-enable):

```powershell
$rg = '<your-rg>'

# Re-tag the RG
az group update -n $rg --tags SecurityControl=ignore CostControl=ignore project=synapse-sre-pilot env=sandbox costCenter=internal

# Re-tag the storage account
$st = az storage account list -g $rg --query '[0].name' -o tsv
az resource tag --tags SecurityControl=ignore CostControl=ignore -g $rg -n $st --resource-type Microsoft.Storage/storageAccounts

# Re-enable public access
az storage account update -n $st -g $rg --public-network-access Enabled
```

OR full Bicep redeploy (idempotent):

```powershell
az deployment sub create --subscription $sub --location swedencentral --template-file main.bicep --parameters main.parameters.json --parameters synapseSqlAdminPassword=(Get-Content .\.synapse-admin-pwd.txt)
```

## Teardown

```powershell
# Soft teardown — pause Spark pool, stop charges
$rg = '<your-rg>'
$wk = az synapse workspace list -g $rg --query '[0].name' -o tsv
az synapse spark pool update --workspace-name $wk -g $rg --name pooldefault --enable-auto-pause true --auto-pause-delay-in-minutes 5

# Hard teardown — delete the RG entirely
az group delete --name $rg --yes --no-wait
```

The Bicep is designed to be re-deployable in <10 min after a hard teardown.

## Known traps

1. **Tenant policies may strip "ignore" bypass tags periodically** — symptom is Storage `BlobNotFound` on existing blobs because public access got re-disabled. Fix: redeploy or re-tag (see above).
2. **Synapse workspace name is globally unique** in the region. The `<suffix>` (6-char) derived from `uniqueString(subscription().id, resourceGroupName)` should keep it stable across redeploys.
3. **Synapse SQL admin password** must be 8+ chars with mix of categories. The deploy script generates a 24-char password with all categories.
4. **Action Group diagnostic settings** — action groups do NOT support resource-level diag settings. Notification delivery results are captured via the **subscription Activity Log** filtered to `Notification` operations. The Bicep wires this for you; without it, SRE Agent can't see delivery failures.
5. **Spark pool auto-pause** — Pipeline C deliberately flips auto-pause to a longer delay to demo pain point #2. Always flip back to 15 min after that test.
