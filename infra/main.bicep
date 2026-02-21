targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment, used for resource naming')
param environmentName string

@minLength(1)
@description('Azure region for all resources')
param location string

var resourceSuffix = take(uniqueString(subscription().id, environmentName, location), 6)
var tags = { 'azd-env-name': environmentName }

resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: 'rg-${environmentName}'
  location: location
  tags: tags
}

module resources './modules/resources.bicep' = {
  name: 'resources'
  scope: rg
  params: {
    location: location
    tags: tags
    resourceSuffix: resourceSuffix
  }
}

// UPPERCASE outputs become azd environment variables
output AZURE_RESOURCE_GROUP string = rg.name
output WEB_URL string = resources.outputs.webUrl
output AZURE_STORAGE_ACCOUNT_NAME string = resources.outputs.storageAccountName
