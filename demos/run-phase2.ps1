# run-phase2.ps1 — Phase 2 end-to-end deploy + run
#
# Per ../PLAN.md Phase 2. Stages data, uploads notebooks, creates pipelines,
# runs them, captures outputs to demos/transcripts/phase2-baseline.md.
#
# Idempotent: safe to re-run. Existing notebooks/pipelines are updated, not duplicated.
#
# Usage:
#   .\run-phase2.ps1 `
#     -Subscription <your-subscription-id> `
#     -ResourceGroup <your-rg> `
#     -Workspace <your-synapse-workspace> `
#     -Storage <your-storage-account>
# Or set the parameters as env vars / pull them from infra/.deployment-output.json.

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Subscription,
  [Parameter(Mandatory = $true)]
  [string]$ResourceGroup,
  [Parameter(Mandatory = $true)]
  [string]$Workspace,
  [Parameter(Mandatory = $true)]
  [string]$Storage,
  [string]$SparkPool = 'pooldefault',
  [switch]$IncludeRunaway,            # set to also run the never-stops Pipeline C (will run until Spark auto-pause)
  [switch]$SkipDataUpload             # skip uploading customers-5col.csv if already there
)

$ErrorActionPreference = 'Stop'
$VerbosePreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot   # repo root
$demos = Join-Path $root 'demos'
$pipes = Join-Path $demos 'pipelines'
$data = Join-Path $demos 'data'
$transcripts = Join-Path $demos 'transcripts'
$transcript = Join-Path $transcripts 'phase2-baseline.md'

function Log($msg) { Write-Host "[run-phase2] $msg" -ForegroundColor Cyan }
function Append($line) { Add-Content -Path $transcript -Value $line }

# ----------------------------------------------------------------------------
# Init transcript
# ----------------------------------------------------------------------------
if (-not (Test-Path $transcripts)) { New-Item -ItemType Directory -Path $transcripts | Out-Null }
@"
# Phase 2 — Failure injection transcript

**Run started:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
**Workspace:** $Workspace
**Storage:** $Storage
**Spark pool:** $SparkPool

---

"@ | Out-File -FilePath $transcript -Encoding utf8

# ----------------------------------------------------------------------------
# Stage data
# ----------------------------------------------------------------------------
if (-not $SkipDataUpload) {
  Log "Uploading customers-5col.csv to $Storage/stage..."
  Append "## Data staging`n"
  $upload = az storage blob upload --account-name $Storage --container-name stage --name 'customers-5col.csv' --file (Join-Path $data 'customers-5col.csv') --auth-mode login --overwrite 2>&1 | Out-String
  Append '```'
  Append $upload.Trim()
  Append '```'
  Append ""
  if ($LASTEXITCODE -ne 0) {
    Log "Upload FAILED. RBAC propagation may need more time. Retrying in 60s..."
    Start-Sleep -Seconds 60
    $upload = az storage blob upload --account-name $Storage --container-name stage --name 'customers-5col.csv' --file (Join-Path $data 'customers-5col.csv') --auth-mode login --overwrite 2>&1 | Out-String
    Append '```'
    Append $upload.Trim()
    Append '```'
    if ($LASTEXITCODE -ne 0) {
      Append "**WARNING:** data upload still failing after retry. Pipeline B will fail to read source CSV. Check 'Storage Blob Data Contributor' role assignment."
    }
  }
} else {
  Log "Skipping data upload (--SkipDataUpload)"
}

# ----------------------------------------------------------------------------
# Upload notebooks (4 of them — A, B, C, E)
# ----------------------------------------------------------------------------
Append "`n## Notebooks`n"
foreach ($nbFile in @('notebook-A-baseline.ipynb','notebook-B-schema-drift.ipynb','notebook-C-runaway.ipynb','notebook-E-hard-failure.ipynb')) {
  $nbName = [IO.Path]::GetFileNameWithoutExtension($nbFile)
  $nbPath = Join-Path $pipes $nbFile
  Log "Uploading notebook $nbName..."
  $out = az synapse notebook create --workspace-name $Workspace --name $nbName --file "@$nbPath" --spark-pool-name $SparkPool 2>&1 | Out-String
  Append "### $nbName"
  if ($LASTEXITCODE -eq 0) { Append "✅ uploaded" } else { Append "❌ FAILED" }
  Append '```'
  Append (($out -split "`n" | Select-Object -First 5) -join "`n")
  Append '```'
  Append ""
}

# ----------------------------------------------------------------------------
# Create / update pipelines (4 — A, B, C, E)
# ----------------------------------------------------------------------------
Append "`n## Pipelines`n"
foreach ($plFile in @('pipeline-A-baseline.json','pipeline-B-schema-drift.json','pipeline-C-runaway-spark.json','pipeline-E-hard-failure.json')) {
  $plName = [IO.Path]::GetFileNameWithoutExtension($plFile)
  $plPath = Join-Path $pipes $plFile
  Log "Creating pipeline $plName..."
  $out = az synapse pipeline create --workspace-name $Workspace --name $plName --file "@$plPath" 2>&1 | Out-String
  Append "### $plName"
  if ($LASTEXITCODE -eq 0) { Append "✅ created" } else { Append "❌ FAILED" }
  Append '```'
  Append (($out -split "`n" | Select-Object -First 5) -join "`n")
  Append '```'
  Append ""
}

# ----------------------------------------------------------------------------
# Trigger the safe pipelines (A, B, E)
# ----------------------------------------------------------------------------
Append "`n## Pipeline runs`n"
$runs = @()
foreach ($pl in @('pipeline-A-baseline','pipeline-B-schema-drift','pipeline-E-hard-failure')) {
  Log "Triggering $pl..."
  $runJson = az synapse pipeline create-run --workspace-name $Workspace --name $pl 2>&1 | Out-String
  Append "### $pl"
  Append '```json'
  Append $runJson.Trim()
  Append '```'
  Append ""
  try {
    $runId = ($runJson | ConvertFrom-Json).runId
    $runs += [pscustomobject]@{ Name = $pl; RunId = $runId }
    Log "  -> runId: $runId"
  } catch {
    Append "**WARNING:** could not parse runId from output."
  }
  Start-Sleep -Seconds 3
}

# ----------------------------------------------------------------------------
# Optional — Pipeline C (runaway)
# ----------------------------------------------------------------------------
if ($IncludeRunaway) {
  Log "Setting Spark pool auto-pause to 30 min (bounds runaway scenario)..."
  az synapse spark pool update --workspace-name $Workspace -g $ResourceGroup --name $SparkPool --enable-auto-pause true --auto-pause-delay-in-minutes 30 | Out-Null
  Log "Triggering pipeline-C-runaway-spark..."
  $runJson = az synapse pipeline create-run --workspace-name $Workspace --name 'pipeline-C-runaway-spark' 2>&1 | Out-String
  Append "### pipeline-C-runaway-spark"
  Append '```json'
  Append $runJson.Trim()
  Append '```'
  Append "**Note:** This pipeline will not finish on its own. It runs until Spark pool auto-pause (currently 30 min)."
  Append "After the demo, restore safe auto-pause:"
  Append '```'
  Append "az synapse spark pool update --workspace-name $Workspace -g $ResourceGroup --name $SparkPool --enable-auto-pause true --auto-pause-delay-in-minutes 15"
  Append '```'
} else {
  Append "`n### pipeline-C-runaway-spark"
  Append "Skipped (re-run with -IncludeRunaway to demo Pain Point #2). Will run until Spark pool auto-pause."
}

# ----------------------------------------------------------------------------
# Wait for runs A/B/E to finish (15 min max each — Spark cold-start dominates)
# ----------------------------------------------------------------------------
Append "`n## Run outcomes (poll until terminal status)`n"
foreach ($r in $runs) {
  Log "Polling $($r.Name) (runId $($r.RunId))..."
  $waitedSec = 0; $maxSec = 1500; $sleepSec = 30
  $status = 'InProgress'
  while ($waitedSec -lt $maxSec -and $status -in @('InProgress','Queued','Started','Cancelling',$null)) {
    Start-Sleep -Seconds $sleepSec
    $waitedSec += $sleepSec
    $statusJson = az synapse pipeline-run show --workspace-name $Workspace --run-id $r.RunId 2>&1 | Out-String
    try {
      $status = ($statusJson | ConvertFrom-Json).status
      Log "  $($r.Name) status after ${waitedSec}s: $status"
    } catch {
      Log "  could not parse status; continuing"
    }
  }
  Append "### $($r.Name)"
  Append "- runId: ``$($r.RunId)``"
  Append "- final status: $status (after ${waitedSec}s)"
  Append '```json'
  Append $statusJson.Trim()
  Append '```'
  Append ""
}

# ----------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------
Append "`n## Summary`n"
Append "- $($runs.Count) safe pipelines triggered (A, B, E). C was $(if ($IncludeRunaway) {'triggered'} else {'skipped'})."
Append "- Allow ~10 min for diagnostic logs to land in LAW before querying via SRE Agent."
Append "- Verify with: ``az monitor log-analytics query --workspace <law-customer-id> --analytics-query 'SynapseIntegrationActivityRuns | take 10'``"
Append "- Phase 3 next: provision SRE Agent (see ../docs/phase3-provisioning-steps.md)"

Log "DONE. Transcript: $transcript"
