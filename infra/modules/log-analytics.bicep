// Log Analytics workspace + workspace-based Application Insights.
// All Synapse + Action Group diagnostic settings target the LAW.
// App Insights gets the same backing LAW so Spark notebook custom events
// land in the same KQL surface as Synapse pipeline telemetry.

@description('Azure region')
param location string

@description('Log Analytics workspace name')
param logAnalyticsName string

@description('Application Insights component name')
param appInsightsName string

@description('Tags inherited from RG')
param tags object

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

resource ai 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'other'
    WorkspaceResourceId: law.id
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

output logAnalyticsWorkspaceId string = law.id
output logAnalyticsName string = law.name
output appInsightsId string = ai.id
output appInsightsName string = ai.name
#disable-next-line outputs-should-not-contain-secrets
output appInsightsConnectionString string = ai.properties.ConnectionString
