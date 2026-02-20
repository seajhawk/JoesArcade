@description('Base name used for all resources (e.g. navalarcade)')
param baseName string = 'navalarcade'

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('GitHub repo owner/name (e.g. seajhawk/JoesArcade)')
param repoUrl string = 'https://github.com/seajhawk/JoesArcade'

@description('Branch to deploy from')
param branch string = 'master'

// ── Storage Account for leaderboard Table Storage ───────────────────────────
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: '${toLower(baseName)}store'
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
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

// ── Static Web App ───────────────────────────────────────────────────────────
resource staticWebApp 'Microsoft.Web/staticSites@2023-01-01' = {
  name: baseName
  location: location
  sku: { name: 'Free', tier: 'Free' }
  properties: {
    repositoryUrl: repoUrl
    branch: branch
    buildProperties: {
      appLocation: '/'
      apiLocation: 'api'
      outputLocation: ''
    }
  }
}

// Inject the storage connection string as an app setting in SWA
resource swaAppSettings 'Microsoft.Web/staticSites/config@2023-01-01' = {
  parent: staticWebApp
  name: 'appsettings'
  properties: {
    STORAGE_CONNECTION_STRING: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
  }
}

// ── Outputs ──────────────────────────────────────────────────────────────────
output staticWebAppUrl string = 'https://${staticWebApp.properties.defaultHostname}'
output staticWebAppApiToken string = staticWebApp.listSecrets().properties.apiKey
output storageAccountName string = storageAccount.name
