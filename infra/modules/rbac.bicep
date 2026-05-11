// Grant Synapse workspace SystemAssigned MI 'Storage Blob Data Contributor'
// on the default Data Lake. Required for the workspace to read/write its
// default storage file system (and for any Spark notebook MI-auth scenarios).

@description('Storage account name to scope the role assignment to')
param storageAccountName string

@description('Synapse workspace MI principal ID')
param synapsePrincipalId string

resource storage 'Microsoft.Storage/storageAccounts@2024-01-01' existing = {
  name: storageAccountName
}

// Storage Blob Data Contributor — built-in role
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storage
  name: guid(storage.id, synapsePrincipalId, storageBlobDataContributorRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: synapsePrincipalId
    principalType: 'ServicePrincipal'
  }
}
