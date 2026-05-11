// =============================================================================
// Synapse + Azure SRE Agent pilot — public template
// Subscription-scoped main template. Creates RG with optional bypass tags,
// then deploys Storage (Data Lake Gen2) + LAW + App Insights + Synapse +
// Action Group + Alert + RBAC.
// =============================================================================

targetScope = 'subscription'

@description('Resource group name')
param resourceGroupName string = 'rg-synapse-sre-pilot'

@description('Azure region. Sweden Central matches SRE Agent GA. East US 2 + Australia East also work.')
param location string = 'swedencentral'

@description('Project resource name prefix. 3-11 lowercase letters/digits.')
@minLength(3)
@maxLength(11)
param namePrefix string = 'srepilot'

@description('Synapse SQL admin login. Cannot be admin/sa/sysadmin/dbo/etc.')
param synapseSqlAdminLogin string = 'synadmin'

@secure()
@description('Synapse SQL admin password. Generate at deploy time; store gitignored in infra/.synapse-admin-pwd.txt.')
param synapseSqlAdminPassword string

@description('Tags applied to RG and all resources. The SecurityControl + CostControl values may be required to bypass tenant policies in some Microsoft-internal subscriptions; safe to leave at defaults for most tenants.')
param tags object = {
  SecurityControl: 'ignore'
  CostControl: 'ignore'
  project: 'synapse-sre-pilot'
  env: 'sandbox'
  costCenter: 'internal'
}

// -----------------------------------------------------------------------------
// Resource group
// -----------------------------------------------------------------------------
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// 6-char deterministic suffix for globally-unique names
var suffix = take(uniqueString(subscription().id, resourceGroupName), 6)

// -----------------------------------------------------------------------------
// Storage (Data Lake Gen2) — managed-identity-only auth, no public access
// -----------------------------------------------------------------------------
module storage 'modules/storage.bicep' = {
  scope: rg
  name: 'storage-deploy'
  params: {
    location: location
    storageAccountName: 'st${namePrefix}${suffix}'
    tags: tags
  }
}

// -----------------------------------------------------------------------------
// Observability — Log Analytics + workspace-based App Insights
// -----------------------------------------------------------------------------
module observability 'modules/log-analytics.bicep' = {
  scope: rg
  name: 'observability-deploy'
  params: {
    location: location
    logAnalyticsName: 'log-${namePrefix}-${suffix}'
    appInsightsName: 'appi-${namePrefix}-${suffix}'
    tags: tags
  }
}

// -----------------------------------------------------------------------------
// Synapse workspace + single Spark pool + diagnostic settings
// -----------------------------------------------------------------------------
module synapse 'modules/synapse.bicep' = {
  scope: rg
  name: 'synapse-deploy'
  params: {
    location: location
    workspaceName: 'synw-${namePrefix}-${suffix}'
    sparkPoolName: 'pooldefault'
    storageAccountName: storage.outputs.storageAccountName
    storageFileSystemName: storage.outputs.synapseFileSystemName
    sqlAdminLogin: synapseSqlAdminLogin
    sqlAdminPassword: synapseSqlAdminPassword
    logAnalyticsWorkspaceId: observability.outputs.logAnalyticsWorkspaceId
    tags: tags
  }
}

// -----------------------------------------------------------------------------
// RBAC — Synapse SystemAssigned MI gets Storage Blob Data Contributor on storage
// (Required for the workspace to read/write its default Data Lake)
// -----------------------------------------------------------------------------
module rbac 'modules/rbac.bicep' = {
  scope: rg
  name: 'rbac-deploy'
  params: {
    storageAccountName: storage.outputs.storageAccountName
    synapsePrincipalId: synapse.outputs.synapseManagedIdentityPrincipalId
  }
}

// -----------------------------------------------------------------------------
// Monitoring — Action Group with deliberately-broken channels (pain point #3),
// alert rule, and AG diagnostic settings -> LAW (CRITICAL for SRE Agent demo)
// -----------------------------------------------------------------------------
module monitoring 'modules/monitoring.bicep' = {
  scope: rg
  name: 'monitoring-deploy'
  params: {
    location: location
    actionGroupName: 'ag-${namePrefix}-${suffix}'
    alertRuleName: 'alert-pipeline-runs-ended'
    synapseWorkspaceId: synapse.outputs.workspaceId
    logAnalyticsWorkspaceId: observability.outputs.logAnalyticsWorkspaceId
    tags: tags
  }
}

// -----------------------------------------------------------------------------
// Outputs — printed by `az deployment sub create` and used by Phase 2 scripts
// -----------------------------------------------------------------------------
output resourceGroupName string = rg.name
output location string = location
output storageAccountName string = storage.outputs.storageAccountName
output storageDfsEndpoint string = storage.outputs.storageDfsEndpoint
output synapseFileSystemName string = storage.outputs.synapseFileSystemName
output synapseWorkspaceName string = synapse.outputs.workspaceName
output synapseWorkspaceId string = synapse.outputs.workspaceId
output sparkPoolName string = synapse.outputs.sparkPoolName
output logAnalyticsWorkspaceName string = observability.outputs.logAnalyticsName
output logAnalyticsWorkspaceId string = observability.outputs.logAnalyticsWorkspaceId
output appInsightsName string = observability.outputs.appInsightsName
output appInsightsConnectionString string = observability.outputs.appInsightsConnectionString
output actionGroupName string = monitoring.outputs.actionGroupName
output actionGroupId string = monitoring.outputs.actionGroupId
output synapseStudioUrl string = 'https://web.azuresynapse.net?workspace=%2Fsubscriptions%2F${subscription().subscriptionId}%2FresourceGroups%2F${rg.name}%2Fproviders%2FMicrosoft.Synapse%2Fworkspaces%2F${synapse.outputs.workspaceName}'

// -----------------------------------------------------------------------------
// Subscription-level Activity Log diagnostic setting -> LAW.
// Action groups don't support resource-level diag settings (API limitation),
// so we capture notification delivery results via the Activity Log at sub scope.
// SRE Agent queries `AzureActivity | where OperationName has "Notification"`
// to investigate Pain Point #3.
// -----------------------------------------------------------------------------
resource subActivityLogDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'synapse-pilot-activitylog-to-law-${suffix}'
  properties: {
    workspaceId: observability.outputs.logAnalyticsWorkspaceId
    logs: [
      {
        category: 'Administrative'
        enabled: true
      }
      {
        category: 'Alert'
        enabled: true
      }
      {
        category: 'ResourceHealth'
        enabled: true
      }
      {
        category: 'ServiceHealth'
        enabled: true
      }
      {
        category: 'Autoscale'
        enabled: true
      }
    ]
  }
}
