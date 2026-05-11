# Runbook: Alert Delivery Failure Investigation

**Pain Point:** #3 (Alert emails never delivered despite "OK" service health dashboard)

> The agent's killshot insight on this pain point reads almost verbatim:
> *"Service Health reports on Azure platform availability, not on whether your action group successfully delivers notifications. An action group with bogus receivers is still a valid Azure resource in a Succeeded provisioning state — it just silently fails at delivery time."*
> Trust `AzureActivity` for `Notification` ops, not the colour of the dashboard tile.

## When to use

Question patterns:
- "Did action group X deliver any notifications?"
- "Why didn't I get an email/Teams message about alert Y?"
- "Has alert Z fired at all this week?"
- "Are my alert delivery channels healthy?"

## Primary KQL — Action group delivery failures (last 24h)

> **Important table-name note (action group diagnostics):** Action groups do NOT support resource-level diagnostic settings. Notification delivery results land in the **subscription Activity Log** (`AzureActivity`) under `OperationName has "Notification"` — provided a subscription-scoped Activity Log diagnostic setting routes those categories to LAW. The Bicep in `infra/main.bicep` creates one named `synapse-pilot-activitylog-to-law-<suffix>`. If your tenant already has another sub-level Activity Log diag setting routing the same data, that one works too.

```kql
// Action group notification attempts in the subscription Activity Log
AzureActivity
| where TimeGenerated > ago(24h)
| where OperationNameValue has "Microsoft.Insights/ActionGroups/Notification"
    or OperationName has "Notification"
| extend
    AGName = tostring(split(_ResourceId, "/")[-1]),
    Channel = tostring(parse_json(Properties_d).notificationChannelType),
    Recipient = tostring(parse_json(Properties_d).recipient),
    DeliveryStatus = ActivityStatusValue
| project TimeGenerated, AGName, Channel, Recipient, DeliveryStatus,
    OperationName, ActivityStatus = ActivityStatusValue,
    Caller, Properties_d
| order by TimeGenerated desc
| take 50
```

If `AzureActivity` is empty for these operations, the sub-level Activity Log diagnostic setting is missing. Verify with:

```powershell
az monitor diagnostic-settings subscription list --subscription <your-subscription-id>
```

Expected: at least one diag setting with `logs[?category == 'Alert']` enabled and a `workspaceId` pointing at the LAW.

## Did the alert actually FIRE? (sanity check before investigating delivery)

```kql
// Was the alert evaluated and did it transition to Fired?
let alertName = "alert-pipeline-runs-ended";
AlertsManagementResources
| where AlertName_s == alertName or properties.essentials.alertRule contains alertName
| where TimeGenerated > ago(24h)
| project TimeGenerated, AlertName_s, AlertState = tostring(properties.essentials.alertState),
    MonitorCondition = tostring(properties.essentials.monitorCondition),
    Severity = tostring(properties.essentials.severity),
    FiredDateTime = todatetime(properties.essentials.startDateTime),
    Description = tostring(properties.essentials.description)
| order by TimeGenerated desc
```

If you don't see entries here, the alert never fired. If you do, but `ActionGroupOperations` shows no delivery attempts → the action group isn't wired correctly. If `ActionGroupOperations` shows attempts but with `DeliveryStatus != "Succeeded"` → **this is pain point #3**.

## Action group full delivery audit (succeeded + failed)

```kql
// Show every notification attempt in the last 24h with status
AzureActivity
| where TimeGenerated > ago(24h)
| where OperationNameValue has "Microsoft.Insights/ActionGroups/Notification"
    or OperationName has "Notification"
| extend
    AGName = tostring(split(_ResourceId, "/")[-1]),
    Channel = tostring(parse_json(Properties_d).notificationChannelType),
    Recipient = tostring(parse_json(Properties_d).recipient),
    DeliveryStatus = ActivityStatusValue
| summarize
    TotalAttempts = count(),
    Succeeded = countif(DeliveryStatus == "Succeeded" or DeliveryStatus == "Success"),
    Failed = countif(DeliveryStatus !in ("Succeeded", "Success", "Started"))
    by AGName, Channel, Recipient
| extend SuccessRatePct = round(Succeeded * 100.0 / TotalAttempts, 1)
| order by Failed desc, TotalAttempts desc
```

## Webhook-specific failure detail (Logic Apps, Teams incoming webhooks, etc.)

```kql
// Webhook delivery failures with HTTP status if recorded
AzureActivity
| where TimeGenerated > ago(24h)
| where OperationName has "Notification"
| extend
    Channel = tostring(parse_json(Properties_d).notificationChannelType),
    HttpStatus = tostring(parse_json(Properties_d).httpStatusCode),
    ErrorMsg = tostring(parse_json(Properties_d).errorMessage),
    AGName = tostring(split(_ResourceId, "/")[-1])
| where Channel in ("Webhook", "WebHook", "LogicApp")
| where ActivityStatusValue !in ("Succeeded", "Success", "Started")
| project TimeGenerated, AGName, HttpStatus, ErrorMsg, ActivityStatusValue, Properties_d
| order by TimeGenerated desc
```

## Email-specific failure detail (SMTP bounces, throttling)

```kql
AzureActivity
| where TimeGenerated > ago(24h)
| where OperationName has "Notification"
| extend
    Channel = tostring(parse_json(Properties_d).notificationChannelType),
    Recipient = tostring(parse_json(Properties_d).recipient),
    ErrorMsg = tostring(parse_json(Properties_d).errorMessage),
    AGName = tostring(split(_ResourceId, "/")[-1])
| where Channel in ("Email", "EmailReceiver")
| where ActivityStatusValue !in ("Succeeded", "Success", "Started")
| project TimeGenerated, AGName, Recipient, ErrorMsg, ActivityStatusValue
| order by TimeGenerated desc
```

## Interpretation guidance

| Symptom | Likely cause | Recommended action |
|---|---|---|
| Alert fired (in `AlertsManagementResources`); no rows in `AzureActivity` for `Notification` ops | Action group not wired to alert OR sub-level Activity Log diag setting missing/broken | Verify action group is in alert's `actions` array. Verify with `az monitor diagnostic-settings subscription list` that an Activity Log → LAW diag setting exists with `Alert` category enabled. |
| `ActivityStatusValue = "Failed"`, Channel = `Email`, errorMessage mentions `bounce` / `5xx` | Recipient mailbox doesn't exist OR is rejecting | Update recipient. **[Pain Point #3]** if the recipient was previously valid. |
| `ActivityStatusValue = "Failed"`, Channel = `Webhook`, httpStatusCode = 401/403 | Auth failure (revoked token, expired SAS, missing AAD permission) | Regenerate webhook signature OR rotate the secret in Key Vault and update AG. **[Pain Point #3]** classic. |
| `ActivityStatusValue = "Failed"`, Channel = `Webhook`, httpStatusCode = 404 | Webhook URL stale (Logic App deleted, Teams channel webhook removed) | Re-create the webhook target; update the AG. |
| `ActivityStatusValue = "Failed"`, httpStatusCode = 429 | Throttled by destination (Teams / Logic App) | Add a queue or use Event Grid; reduce alert noise; merge alerts. |
| Service Health dashboard shows the AG as "OK" but failures present | The dashboard reflects RULE health, not delivery success | **[Pain Point #3] core insight.** Tell the customer: trust `AzureActivity` for `Notification` ops, not the colour of the dashboard tile. |

## Template context

The action group `ag-<prefix>-<suffix>` in this template has TWO deliberately broken receivers:
1. `bad@invalid.invalid` (RFC 2606 reserved TLD; will always bounce)
2. A Logic App webhook with a revoked SAS signature (will return 401/403)

Expected SRE Agent answer to "Did action group X deliver any notifications?":
> Action group `ag-<prefix>-<suffix>` was invoked N times in the last 24h. **Zero notifications delivered.** Email channel to `bad@invalid.invalid`: N attempts, all failed (SMTP bounce). Webhook channel `RevokedLogicAppHook`: N attempts, all failed (HTTP 403). The Service Health dashboard shows "OK" because the alert rule itself is evaluating correctly — but the delivery path is 100% broken. Recommended action: replace the bad email recipient and rotate the Logic App SAS signature. **[Pain Point #3]**

> Source data: `AzureActivity` table, filtered to `OperationName has "Notification"` (subscription-level Activity Log routed to LAW via the `synapse-pilot-activitylog-to-law-<suffix>` diagnostic setting). Action groups do not support resource-level diagnostic settings — the subscription Activity Log is the only path.
