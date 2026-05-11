# Phase 3.5 — Proactive loop wiring (alert → SRE Agent → Teams)

**Why this doc:** Phase 3.5 is the killshot demo. Vanilla SRE Agent is reactive (you ask, it answers). The proactive loop turns a fired alert into an autonomous triage report posted to Teams BEFORE the on-call wakes up.

**Per:** `../PLAN.md` Phase 3.5

**Estimated time:** 1-2 hours.
**Prereq:** Phase 3 complete (SRE Agent provisioned, smoke prompts passing ≥ 12/15 average).

## Architecture

```
┌──────────────────────────┐         ┌──────────────────────┐
│  Synapse pipeline runs   │         │  Action Group        │
│  → metric                │ ──────► │  ag-<prefix>-<suffix>│
│  IntegrationActivity     │         │                      │
│   RunsEnded > 0          │         │  ├─ Email (broken)   │ ─❌─> bounces
└──────────────────────────┘         │  ├─ Webhook (broken) │ ─❌─> 403
                                      │  └─ SRE Agent       │ ─✓─► triage
                                      │     webhook (NEW)   │       │
                                      └──────────────────────┘       │
                                                                     ▼
                                              ┌─────────────────────────────────────┐
                                              │  Azure SRE Agent                    │
                                              │  receives alert payload             │
                                              │  ├─ runs runbook KQL                │
                                              │  ├─ generates 200-word RCA          │
                                              │  └─ posts to Teams via connector    │
                                              └─────────────────────────────────────┘
                                                          │
                                                          ▼
                                              ┌─────────────────────────────────────┐
                                              │  Teams channel                      │
                                              │  "Synapse SRE Triage"               │
                                              │  → On-call sees RCA, not raw alert  │
                                              └─────────────────────────────────────┘
```

## Step 1 — Create the Teams channel

1. In Microsoft Teams, create a private channel (or use an existing test channel).
2. Recommended name: `Synapse SRE Triage`
3. Members: yourself + reviewer(s) for the demo.
4. Note the channel name + parent team for the SRE Agent connector configuration in Step 3.

## Step 2 — Get the SRE Agent webhook URL

The SRE Agent exposes an "Agent Hooks" endpoint that accepts incoming alert payloads. Per `learn.microsoft.com/en-us/azure/sre-agent/tutorial-agent-hooks`:

1. Open the SRE Agent in the portal
2. **Agent Hooks** blade (or "Webhooks" / "Integrations" — naming may vary)
3. **+ New hook**:
   - Name: `synapse-pipeline-alert-triage`
   - Trigger source: Action Group
   - Subagent to invoke: `synapse_expert` (after Phase 4 upload) — or leave default vanilla agent for first test
   - Output channel: Teams (configure in Step 3 first if not already set up)
4. Click Create
5. Copy the **Webhook URL** — looks like `https://<region>.azuresre.ai/api/hooks/<guid>?code=<sas>`
6. Save it for Step 4 (treat the `code=` SAS like any other secret — do not commit it)

## Step 3 — Configure the Teams connector on the SRE Agent

In the SRE Agent portal:

1. **Connectors** blade → **+ Microsoft Teams**
2. Authenticate as your account (SSO)
3. Select the team and channel from Step 1
4. Test the connection (Send test message button) — confirm a message appears in Teams
5. Save the connector configuration

## Step 4 — Add the SRE Agent webhook to the action group

```powershell
$sub = '<your-subscription-id>'
$rg = '<your-rg>'
$agName = (az monitor action-group list -g $rg --query '[0].name' -o tsv)
$sreWebhookUrl = '<paste webhook URL from Step 2>'

az monitor action-group update -n $agName -g $rg --add-action webhook `
  SREAgentTriage `
  $sreWebhookUrl
# If --add-action syntax differs in your CLI version, recreate with all three actions:
# az monitor action-group create --name $agName --resource-group $rg \
#   --action webhook SREAgentTriage $sreWebhookUrl `
#   --action email BadEmailRecipient bad@invalid.invalid `
#   --action webhook RevokedLogicAppHook '<your-broken-webhook-url>'

# Verify
az monitor action-group show -n $agName -g $rg --query "{webhooks:webhookReceivers, emails:emailReceivers}" -o json
```

The action group should now have THREE channels:
1. `BadEmailRecipient` (broken — for pain point #3 demo)
2. `RevokedLogicAppHook` (broken — for pain point #3 demo)
3. **`SREAgentTriage` (working — the new one)**

## Step 5 — Trigger an alert to test the loop end-to-end

Run any pipeline (the alert rule fires on `IntegrationActivityRunsEnded > 0`):

```powershell
$sub = '<your-subscription-id>'
$rg = '<your-rg>'
$wk = (az synapse workspace list -g $rg --query '[0].name' -o tsv)

# Run pipeline B (schema drift) to make the demo story interesting
az synapse pipeline create-run --workspace-name $wk -g $rg --name 'pipeline-B-schema-drift'
```

Wait 1-5 min for the alert to fire and the agent to process.

## Step 6 — Verify the loop fired

```powershell
# Check the action group invocation in LAW (via subscription Activity Log)
$law = (az monitor log-analytics workspace show -g $rg -n (az monitor log-analytics workspace list -g $rg --query '[0].name' -o tsv) --query customerId -o tsv)

az monitor log-analytics query --workspace $law --analytics-query @"
AzureActivity
| where TimeGenerated > ago(15m)
| where OperationName has 'Notification'
| project TimeGenerated, OperationName, ActivityStatus, Properties_d
| order by TimeGenerated desc
"@
```

Expected:
- Email channel `BadEmailRecipient`: ActivityStatus = Failed
- Webhook channel `RevokedLogicAppHook`: ActivityStatus = Failed
- Webhook channel `SREAgentTriage`: ActivityStatus = Succeeded

## Step 7 — Verify the Teams post

Open the Teams channel from Step 1. Within 5 min of the alert firing, expect a posted message authored by the SRE Agent containing:
- Alert name + affected resource
- A KQL-grounded RCA (200ish words)
- A recommended next action
- The pain-point label (`[Pain Point #N]`) if subagent is wired (Phase 4)

If no message arrives:
1. Check the SRE Agent's "Agent Hooks" blade for failure logs
2. Check the Teams connector status (Step 3)
3. Check that the webhook URL hasn't expired (re-create if so)

## Step 8 — Repeat 3 times for confidence

Per the Phase 3.5 acceptance gate, run the loop 3 times with slight variation:
1. Trigger via pipeline B (schema drift)
2. Trigger via pipeline E (hard failure)
3. Trigger via pipeline C (runaway Spark — wait for the long auto-pause to fire, or test by manually firing the metric)

Each run should produce a Teams message within 5 min, and each message should contain a specific RCA scoring ≥ 12/15 on the Phase 3 rubric.

## Acceptance gates

- ✅ Teams message arrives within 5 min on all 3 trigger runs
- ✅ Each message has a specific RCA (not generic "investigate this alert")
- ✅ The story tells itself: "Action group's primary channels failed. The SRE Agent channel did not. The on-call engineer received a triage report instead of a 3am page with no context."
- ⚠️ If RCA quality is lower than Phase 3 interactive Q&A → the agent has less prompt context when triggered by webhook than when asked directly. Mitigate via Phase 4 subagent's KQL runbooks.

## Recording for a deck

Once the loop is reliable, screen-record the end-to-end flow:
1. Show the alert rule in the portal (state = Fired)
2. Show `AzureActivity` filtered to `Notification` operations — primary channels = Failed, SRE Agent = Succeeded
3. Show the Teams channel — agent's RCA message
4. Switch to Synapse Studio — show the actual pipeline that failed
5. Voiceover: "30 min of triage saved per incident. The on-call engineer wakes up to context, not a cryptic alert."

This 3-min recording is the demo Slide 4 of any readout deck you build on top of this template.
