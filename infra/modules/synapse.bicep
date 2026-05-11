// Synapse workspace with single Spark pool + diagnostic settings -> LAW.
// SystemAssigned MI is granted Storage Blob Data Contributor in rbac.bicep.
// No managed VNet, no dedicated SQL pool — minimum surface for Phase 1.

@description('Azure region')
param location string

@description('Synapse workspace name. Globally unique.')
param workspaceName string

@description('Spark pool name. 1-15 alphanumeric, no hyphens.')
@maxLength(15)
param sparkPoolName string

@description('Storage account name (referenced via existing resource for ID/dfs).')
param storageAccountName string

@description('Synapse default workspace file system inside the storage account.')
param storageFileSystemName string

@description('Synapse SQL admin login. Cannot be admin/sa/etc.')
param sqlAdminLogin string

@secure()
@description('Synapse SQL admin password. Strong password required.')
param sqlAdminPassword string

@description('Log Analytics workspace ID for diagnostic settings')
param logAnalyticsWorkspaceId string

@description('Tags inherited from RG')
param tags object

// Reference the storage account created by storage.bicep
resource storage 'Microsoft.Storage/storageAccounts@2024-01-01' existing = {
  name: storageAccountName
}

resource workspace 'Microsoft.Synapse/workspaces@2021-06-01' = {
  name: workspaceName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    defaultDataLakeStorage: {
      accountUrl: 'https://${storage.name}.dfs.${environment().suffixes.storage}'
      filesystem: storageFileSystemName
      resourceId: storage.id
      createManagedPrivateEndpoint: false
    }
    sqlAdministratorLogin: sqlAdminLogin
    sqlAdministratorLoginPassword: sqlAdminPassword
    publicNetworkAccess: 'Enabled'
    managedResourceGroupName: '${resourceGroup().name}-managed-${take(uniqueString(workspaceName), 6)}'
  }
}

// Allow Azure-internal services (e.g., SRE Agent) to reach Synapse SQL endpoint
resource firewallAllowAzure 'Microsoft.Synapse/workspaces/firewallRules@2021-06-01' = {
  parent: workspace
  name: 'AllowAllWindowsAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Single small Spark pool with 15-min auto-pause (default).
// Pipeline C (runaway Spark scenario) will temporarily flip auto-pause to 12h
// via `az synapse spark pool update`, then back.
resource sparkPool 'Microsoft.Synapse/workspaces/bigDataPools@2021-06-01' = {
  parent: workspace
  name: sparkPoolName
  location: location
  tags: tags
  properties: {
    sparkVersion: '3.4'
    nodeCount: 3
    nodeSize: 'Small'
    nodeSizeFamily: 'MemoryOptimized'
    autoScale: {
      enabled: false
      minNodeCount: 3
      maxNodeCount: 3
    }
    autoPause: {
      enabled: true
      delayInMinutes: 15
    }
    isComputeIsolationEnabled: false
    sessionLevelPackagesEnabled: false
    cacheSize: 0
    dynamicExecutorAllocation: {
      enabled: false
    }
  }
}

// Diagnostic settings: ALL log categories + AllMetrics -> LAW.
// SRE Agent will query SynapseIntegrationPipelineRuns, SynapseBigDataPoolApplicationsEnded, etc.
resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: workspace
  name: 'synapse-to-law'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output workspaceId string = workspace.id
output workspaceName string = workspace.name
output sparkPoolName string = sparkPool.name
output synapseManagedIdentityPrincipalId string = workspace.identity.principalId
