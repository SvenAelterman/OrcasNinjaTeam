param acrName string
param location string = resourceGroup().location
param keyVaultPrivateDnsZoneResourceId string
param privateEndpointSubnetResourceId string
param uamiPrincipalId string
param tags object?
param enableAvmTelemetry bool

@secure()
param mySqlUsername string
@secure()
param mySqlPassword string

resource acr 'Microsoft.ContainerRegistry/registries@2025-11-01' existing = {
  name: acrName
}

module keyVaultModule 'br/public:avm/res/key-vault/vault:0.14.0' = {
  name: 'keyVaultModule'
  params: {
    name: 'MySQLLTR-prod-kv-01${take(uniqueString(resourceGroup().id), 4)}'
    location: location
    enableRbacAuthorization: true
    secrets: [
      {
        name: 'MySqlUsername'
        value: mySqlUsername
      }
      {
        name: 'MySqlPassword'
        value: mySqlPassword
      }
      {
        name: 'ContainerRegistryUsername'
        value: acr.listCredentials().username
      }
      {
        name: 'ContainerRegistryPassword'
        value: acr.listCredentials().passwords[0].value
      }
    ]

    publicNetworkAccess: 'Disabled'

    privateEndpoints: [
      {
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: keyVaultPrivateDnsZoneResourceId
            }
          ]
        }
        subnetResourceId: privateEndpointSubnetResourceId
        service: 'vault'
      }
    ]

    roleAssignments: [
      {
        principalId: uamiPrincipalId
        roleDefinitionIdOrName: 'Key Vault Secrets User'
        principalType: 'ServicePrincipal'
      }
      {
        principalId: deployer().objectId
        roleDefinitionIdOrName: 'Key Vault Administrator'
        principalType: 'User'
      }
    ]

    enableTelemetry: enableAvmTelemetry
    tags: tags
  }
}
