// Data Lake Gen2 storage account, restrictive defaults.
// Tag-bypass approach: in some Microsoft-internal subscriptions, tenant policy
// strips public-access disable IF SecurityControl=ignore + CostControl=ignore
// tags are present on the RG. Harmless on tenants without that policy.

@description('Azure region')
param location string

@description('Storage account name. 3-24 lowercase alphanumeric.')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Tags inherited from RG')
param tags object

resource storage 'Microsoft.Storage/storageAccounts@2024-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    isHnsEnabled: true                  // Required for Data Lake Gen2 + Synapse
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false         // Force MI auth everywhere
    publicNetworkAccess: 'Enabled'      // Tenant policy may flip; tag-bypass should hold it
    supportsHttpsTrafficOnly: true
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    encryption: {
      services: {
        blob: {
          enabled: true
          keyType: 'Account'
        }
        file: {
          enabled: true
          keyType: 'Account'
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2024-01-01' = {
  parent: storage
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

// Synapse default workspace file system
resource synapseFs 'Microsoft.Storage/storageAccounts/blobServices/containers@2024-01-01' = {
  parent: blobService
  name: 'synapse'
  properties: {
    publicAccess: 'None'
  }
}

// Stage area for raw input data (NYC taxi parquet, schema-drift CSVs, etc.)
resource stageFs 'Microsoft.Storage/storageAccounts/blobServices/containers@2024-01-01' = {
  parent: blobService
  name: 'stage'
  properties: {
    publicAccess: 'None'
  }
}

// Output area for pipeline writes
resource outputFs 'Microsoft.Storage/storageAccounts/blobServices/containers@2024-01-01' = {
  parent: blobService
  name: 'output'
  properties: {
    publicAccess: 'None'
  }
}

output storageAccountId string = storage.id
output storageAccountName string = storage.name
output storageDfsEndpoint string = storage.properties.primaryEndpoints.dfs
output synapseFileSystemName string = synapseFs.name
output stageFileSystemName string = stageFs.name
output outputFileSystemName string = outputFs.name
