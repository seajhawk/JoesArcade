targetScope = 'resourceGroup'

param location string = resourceGroup().location
param tags object = {}
param resourceSuffix string

// ── Storage Account (Standard LRS — cheapest, Table Storage for leaderboard) ──
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  // Storage account names: 3–24 chars, lowercase alphanumeric only, globally unique
  name: 'stnaval${resourceSuffix}'
  location: location
  tags: tags
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource leaderboardTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-01-01' = {
  parent: tableService
  name: 'leaderboard'
}

// ── Azure Static Web Apps (Free tier) ────────────────────────────────────────
resource staticWebApp 'Microsoft.Web/staticSites@2022-09-01' = {
  name: 'swa-naval-${resourceSuffix}'
  location: location
  // azd-service-name tag links this resource to the 'web' service in azure.yaml
  tags: union(tags, { 'azd-service-name': 'web' })
  sku: {
    name: 'Free'
    tier: 'Free'
  }
  properties: {
    buildProperties: {
      appLocation: '/'
      apiLocation: 'api'
      outputLocation: 'public'
    }
  }
}

// Wire the storage connection string into SWA app settings
// Note: upgrade to Standard tier + Managed Identity to eliminate the connection string
resource swaSettings 'Microsoft.Web/staticSites/config@2022-09-01' = {
  parent: staticWebApp
  name: 'appsettings'
  properties: {
    STORAGE_CONNECTION_STRING: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
  }
}

output webUrl string = 'https://${staticWebApp.properties.defaultHostname}'
output storageAccountName string = storageAccount.name
