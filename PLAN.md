# PLAN — Synapse + Azure SRE Agent pilot

**Goal:** Validate that **Azure SRE Agent** can investigate four common Synapse pain points by reproducing them in an isolated sandbox and grading the agent's responses on a documented rubric. **Proof first, deck later.**

## Hard constraints

| Constraint | Where it bites |
|---|---|
| **Tenant policy posture** | If your subscription enforces `disableLocalAuth: true` (storage + cog services), `publicNetworkAccess: Disabled`, NSG injection on VMs, or `allowBlobPublicAccess: false`, the Bicep needs the tag-bypass + re-enable steps documented in `infra/README.md`. |
| **Marketplace activation gates** | If your subscription gates Marketplace SaaS plans, verify SRE Agent provisioning succeeds before relying on it (SRE Agent uses Azure-hosted models under the standard Azure billing path — should not be Marketplace-gated, but verify on first deploy). |
| **Region = Sweden Central (or East US 2 / Australia East)** | SRE Agent GA today only in those regions. Pick the one that matches your data residency story. |
| **No production data** | Internal-first. Use synthetic data only (`customers-5col.csv` ships in `demos/data/`). |
| **Cost ceiling** | Default ceiling: **€60/day soft, €100/day hard**. The disciplined burn for this template is €2-6/day. |
| **Firewall** | Allowlist `*.azuresre.ai` per `learn.microsoft.com/en-us/azure/sre-agent/usage` — verify on the corp / VPN profile before Phase 3. |

## The four pain points → test scenarios

| # | Pain point | Test scenario (synthetic, in this sandbox) |
|---|---|---|
| 1 | Pipelines randomly fail or silently skip data with no clear logs | **Pipeline B** — Spark notebook with **schema drift**: source CSV has 5 columns, sink Parquet writes 4, the `loyalty_tier` column is silently dropped. Pipeline succeeds with wrong-shape data and no warning. |
| 2 | Spark/SQL clusters sometimes never auto-stop | **Pipeline C** — Spark notebook with `while True: time.sleep(60)` infinite loop; bounded only by Spark pool auto-pause. |
| 3 | Alert emails never delivered despite service health "OK" | **Action group** — alert rule fires but action group has a deliberately misconfigured email recipient (`bad@invalid.invalid` — RFC 2606 reserved TLD that always bounces) + a webhook with a revoked SAS signature (HTTP 403/401). |
| 4 | Root-cause analysis hard without deep log access | **Composite** — every scenario above plus a hard-failure pipeline E (missing source file). Test SRE Agent's natural-language RCA quality on each. |
| **Baseline** | (control) | **Pipeline A** — read public NYC Yellow Taxi parquet from Azure Open Datasets, succeeds normally. |

## 5-phase plan

### Phase 1 — Provisioning (~2-3 hours)

**Bicep template** in `infra/`:

- Single resource group `<your-rg>` in `swedencentral`
- `synw-<prefix>-<suffix>` Synapse workspace
  - **Single Apache Spark pool** `pooldefault` (Small, 3 nodes, 15 min auto-pause). Pipeline C's runaway test temporarily flips auto-pause to a longer delay, then back.
  - **No dedicated SQL pool** (saves €€€; Spark pool covers pain points #1-2)
  - Integration runtime: `AutoResolveIntegrationRuntime` (default)
  - Managed identity: SystemAssigned
- `st<prefix><suffix>` Storage (Data Lake Gen2, hierarchical namespace)
- `log-<prefix>-<suffix>` Log Analytics workspace
- `appi-<prefix>-<suffix>` Application Insights (workspace-based)
- **Diagnostic settings on Synapse → LAW**: ALL categories (`SynapseRbacOperations`, `GatewayApiRequests`, `BuiltinSqlReqsEnded`, `IntegrationPipelineRuns`, `IntegrationActivityRuns`, `IntegrationTriggerRuns`, `BigDataPoolApplicationsEnded`, etc.)
- **Subscription-scoped Activity Log diagnostic setting → LAW**: enable `Alert`, `Administrative`, `ResourceHealth`, `ServiceHealth`, `Autoscale` categories. **CRITICAL** for pain point #3 — action groups do NOT support resource-level diagnostic settings; the subscription Activity Log is the only path to capture notification delivery results in LAW.
- **Action group `ag-<prefix>-<suffix>`** with the deliberately misconfigured channels (Pipeline D test target)
- **Metric alert rule** `alert-pipeline-runs-ended` on `Microsoft.Synapse/workspaces` `IntegrationActivityRunsEnded > 0`
- **RBAC matrix:**
  - You: `Owner` on the RG
  - Synapse workspace MI: `Storage Blob Data Contributor` on the storage account (wired in Bicep)
  - **SRE Agent MI** (created in Phase 3, but plan ahead): `Reader` on RG, `Log Analytics Reader` on LAW, `Monitoring Reader` on subscription scope, `Reader` + `Synapse Monitoring Operator` on the Synapse workspace

**Cost estimate (left running 24/7):**

| Component | Cost / day (disciplined) | Cost / day (worst case, no auto-pause) |
|---|---|---|
| Spark pool (single, auto-pause 15min, idle most of day) | ~€0.50 | ~€8 (pipeline C left running 12h) |
| Storage (data lake, < 10 GB) | ~€0.05 | ~€0.05 |
| Log Analytics (PAYG, low volume) | ~€1 | ~€2 |
| App Insights (low volume) | ~€0.20 | ~€0.50 |
| Action group + alert rule | €0 | €0 |
| **Subtotal (no SRE Agent yet)** | **~€2/day** | **~€11/day** |
| Synapse pipeline runs (per execution) | ~€0.05 each | — |
| SRE Agent (added Phase 3, ~4 AAU/h always-on + ~35 AAU/incident) | ~€8/day idle, ~€15/day during active testing | — |

**Realistic burn:** €3-8/day if disciplined.

**Acceptance:** `az group show -n <your-rg>` returns 200, Synapse Studio loads, sample copy from public NYC taxi parquet succeeds.

### Phase 2 — Failure injection (~2 hours)

Create the 4 pipelines + 1 action group as above. Run each once to confirm it produces the expected (mis)behaviour:

| Scenario | Confirmation |
|---|---|
| A — baseline | ~2M rows read from public NYC taxi parquet, status SUCCEEDED |
| B — schema drift | Source CSV gains an unexpected column → sink Parquet truncates → SUCCEEDED with wrong-shape data, no warning |
| C — never-stop Spark | Spark application running for >1h with no progress (bounded by auto-pause) |
| D — alert never delivered | Alert fires (visible in `AzureActivity`); action group has revoked Logic App webhook + bounced SMTP recipient. `AzureActivity` filtered to `Notification` operations records both delivery failures. |
| E — hard failure | Pipeline FAILED with `AnalysisException` / `BlobNotFound` |

**Acceptance:** All 5 scenarios reproduce reliably (run each twice). Capture screenshots + Synapse Studio links in `demos/transcripts/phase2-baseline.md`.

### Phase 3 — Azure SRE Agent provisioning + smoke (~2 hours)

1. **Prereqs:**
   - `Microsoft.App` resource provider registered in your subscription
   - `*.azuresre.ai` allowlisted on corp firewall
   - User has `User Access Administrator` (RBAC required for SRE Agent's MI assignments)
2. **Create:** Portal → Create → Azure SRE Agent → name `sre-<prefix>-pilot` → region `swedencentral` → resource group `<your-rg>` → **Reader mode** (prod-safe). Click-by-click in `docs/phase3-provisioning-steps.md`.
3. **Attach:** point the agent at `<your-rg>` (single RG, includes Synapse + LA + Storage + alert rule)
4. **Attach KQL runbooks as agent knowledge** (collapses Phase 4 — see Phase 4 note below): upload the 4 `.kql.md` files from `runbooks/` to the agent's knowledge base.
5. **Smoke prompts** (capture verbatim Q&A under `demos/transcripts/phase3-smoke-prompts.md`):
   - "What Synapse pipelines failed in the last 24 hours?"
   - "Show me Spark pool applications that have been running for more than 6 hours"
   - "Did action group `ag-<prefix>-<suffix>` deliver any notifications in the last day?"
   - "Why did pipeline `pipeline-B-schema-drift` succeed but produce wrong-shape data?"
   - "Which Synapse pipeline runs in this RG had silent data anomalies?"
6. **Correctness rubric** (write the answer key BEFORE running prompts):
   - For each prompt, author the expected RCA in `demos/transcripts/phase3-answer-key.md`
   - Grade each agent response on three axes (1-5 each; 12+ to pass): Specificity, Citation quality, Recommendation usefulness

**Acceptance gates:**
- ✅ All 5 questions score ≥ 12/15 on the rubric
- ✅ Each answer is grounded in actual log evidence (KQL query shown, run IDs cited)
- ✅ Pain point #3 — agent cites `AzureActivity` rows (or `ActionGroupOperations` if your tenant has it) showing delivery_status = Failed for both the Logic App webhook AND the SMTP recipient

### Phase 3.5 — Proactive loop (~1-2 hours)

> **Why this exists:** Vanilla SRE Agent is *reactive* — it answers when asked. The killshot demo is *proactive* triage: alert fires → SRE Agent investigates → posts a 200-word RCA to Teams BEFORE the on-call engineer wakes up.

1. **Wire Teams channel** for the SRE Agent — built-in connector per `learn.microsoft.com/en-us/azure/sre-agent/connectors`.
2. **Configure SRE Agent webhook** as one of the action group's notification targets (alongside the deliberately-broken email + Logic App webhook from Phase 1's setup).
3. **Trigger a pipeline failure** to fire the alert.
4. **Verify** within 5 min:
   - Action group invocation visible in `AzureActivity` (`Notification` operations) with bad-email + bad-webhook = Failed
   - SRE Agent webhook = Succeeded
   - Teams channel receives a posted message authored by the agent containing: the alert name, the affected resource, the agent's KQL-grounded RCA, and a recommended next action
5. **Repeat 3 times** with slight variation (different pipeline failure, different alert) to confirm the loop is reliable, not lucky.

**Acceptance gates:**
- ✅ Teams message arrives within 5 min of alert firing on all 3 trigger runs
- ✅ Each Teams message contains a specific RCA (not generic "investigate this alert" text)
- ✅ The story tells itself: *"Action group's primary channels failed. The SRE Agent channel did not. The on-call engineer received a triage report instead of a 3am page with no context."*

### Phase 4 — Custom `synapse_expert` subagent (~3 hours, optional)

> **Note on Phase 3+4 collapse.** In the reference run, Phase 3 (vanilla agent) and Phase 4 (custom subagent) were collapsed into one pass. Attaching the runbook `.md` files as agent knowledge during onboarding gave the vanilla agent the same KQL coverage the subagent would have provided. The `runbooks/synapse_expert.yaml` file is preserved as a template for SRE Agent canvases that prefer an explicit subagent definition.

1. Author / customise `runbooks/synapse_expert.yaml` (Agent Canvas YAML format per `learn.microsoft.com/en-us/azure/sre-agent/sub-agents`)
2. Author 4 KQL runbooks in `runbooks/*.kql.md` — one per pain point (already shipped)
3. **Re-run the 5 smoke prompts** prefixed with `/agent synapse_expert`. Capture under `demos/transcripts/phase4-subagent.md`.

**Acceptance gates:**
- ✅ Subagent answer ≥ what an in-house Synapse SRE would write in 5 min. Score each response on the same Phase 3 rubric; pass = average ≥ 13/15 across the 5 prompts AND strictly higher than vanilla on at least 3 of 5.

### Phase 5 — Customer readout (deck) — out of scope for this template

Slide outline the template would support if you build a deck:

- Slide 1: The 4 pain points (verbatim from your customer's framing)
- Slide 2: Why generic alerting failed
- Slide 3: Azure SRE Agent overview (GA, regions, pricing)
- Slide 4: Demo recording (3-4 min screen capture)
- Slide 5: Custom subagent pattern (`synapse_expert` YAML excerpt)
- Slide 6: Teams channel as the alert path (bypassing broken SMTP)
- Slide 7: Cost analysis (per-day burn at customer scale)
- Slide 8: Recommended pilot timeline (2-week joint pilot, scope, owners, success criteria)
- Slide 9: Next steps + ownership table

## Daily teardown protocol

At the end of each work session, if **not actively running tests**:

```bash
# Pause the Spark pool (saves ~€8/day)
az synapse spark pool update \
  --workspace-name synw-<prefix>-<suffix> \
  --resource-group <your-rg> \
  --name pooldefault \
  --enable-auto-pause true --auto-pause-delay-in-minutes 5

# OR full teardown between phases (if no work for >3 days):
az group delete --name <your-rg> --yes --no-wait
```

The Bicep is designed to be re-deployable in <10 min. **Never let the Spark pool idle for more than 24h without auto-pause set.**

## Risks & mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Tenant policies block Synapse provisioning | Medium | Pre-test storage + cog services with `disableLocalAuth: true` policies in Bicep dry-run; use the tag-bypass approach in `infra/README.md`. |
| Marketplace gate blocks SRE Agent | Low (SRE Agent uses Azure-hosted models, not Marketplace MaaS) | If symptom appears (`quotaId: MSDN_*` errors), open a support ticket. |
| Corp firewall doesn't allow `*.azuresre.ai` | Medium | Test from corp + VPN profiles before Phase 3; document workaround if blocked. |
| SRE Agent can't see Synapse resources due to RBAC | Medium | Pre-grant SRE Agent's MI `Reader` on the RG + `Log Analytics Reader` on the LA workspace + `Synapse Monitoring Operator` on the Synapse workspace; verify in Phase 3 step 1. |
| Cost overrun (>€100/day) | Low | Daily teardown protocol + budget alert at €50/day on the RG. |
| Custom subagent quality not noticeably better than vanilla | Medium | Phase 4 acceptance gate forces revision; in the reference run, vanilla + KQL knowledge was already good enough — see the Phase 3+4 collapse note. |

## Tracking

Per-phase progress, smoke transcripts, lessons, and decisions land in:

- `demos/transcripts/<date>-<scenario>.md` — per-test verbatim Q&A
- `infra/README.md` — Bicep deployment + teardown commands
- `runbooks/README.md` — KQL runbook index + subagent YAML
- `docs/customer-readout-summary.md` — narrative summary
