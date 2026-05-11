// Action Group with deliberately-broken channels (Pain Point #3 demo)
// + alert rule.
//
// NOTE on action group diagnostic settings: Azure Monitor does NOT support
// resource-level diagnostic settings on `microsoft.insights/actionGroups`.
// To capture action group delivery results in LAW, configure a SUBSCRIPTION-
// SCOPED Activity Log diagnostic setting (done in main.bicep at sub scope).
// SRE Agent then queries `AzureActivity` filtered to `Notification` operations.
// See runbooks/synapse-alert-delivery.kql.md for the KQL.

@description('Azure region (alert rule location; action group is always Global)')
param location string

@description('Action group name')
param actionGroupName string

@description('Alert rule name')
param alertRuleName string

@description('Synapse workspace resource ID (alert scope)')
param synapseWorkspaceId string

@description('Log Analytics workspace ID (used for cross-reference; AG diag settings live at sub scope)')
param logAnalyticsWorkspaceId string

@description('Tags inherited from RG')
param tags object

// Action group with two deliberately-broken receivers.
// A third receiver (SRE Agent webhook) gets added in Phase 3.5 once the agent exists.
resource ag 'Microsoft.Insights/actionGroups@2024-10-01-preview' = {
  name: actionGroupName
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: 'SREPilot'
    enabled: true
    emailReceivers: [
      {
        name: 'BadEmailRecipient'
        emailAddress: 'bad@invalid.invalid'
        useCommonAlertSchema: true
      }
    ]
    webhookReceivers: [
      {
        name: 'RevokedLogicAppHook'
        serviceUri: 'https://example-logic-app.westeurope.logic.azure.com:443/workflows/00000000000000000000000000000000/triggers/manual/paths/invoke?api-version=2016-10-01&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=invalid_revoked_signature_for_demo_purposes_only'
        useCommonAlertSchema: true
        useAadAuth: false
      }
    ]
  }
}

// CRITICAL diagnostic settings — without this, SRE Agent cannot see
// delivery failure evidence for pain point #3.
// REMOVED 2026-05-11: Action groups do NOT support resource-level diagnostic
// settings (API rejects with ResourceTypeNotSupported). Activity Log at
// subscription scope is the correct path — wired in main.bicep.

// Alert rule — fires whenever a Synapse pipeline activity completes.
// Low threshold by design: we want frequent firings to exercise the
// (deliberately broken) action group delivery path during demos.
resource alert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: alertRuleName
  location: 'global'
  tags: tags
  properties: {
    description: 'Fires whenever a Synapse pipeline activity completes. Intentionally low threshold to exercise the alert delivery path for pain point #3 demo.'
    severity: 3
    enabled: true
    scopes: [
      synapseWorkspaceId
    ]
    targetResourceType: 'Microsoft.Synapse/workspaces'
    targetResourceRegion: location
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'PipelineActivityRunsEnded'
          metricNamespace: 'Microsoft.Synapse/workspaces'
          metricName: 'IntegrationActivityRunsEnded'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
    actions: [
      {
        actionGroupId: ag.id
      }
    ]
  }
}

output actionGroupName string = ag.name
output actionGroupId string = ag.id
output alertRuleName string = alert.name
