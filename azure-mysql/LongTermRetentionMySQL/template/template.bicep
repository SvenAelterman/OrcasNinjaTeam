param storageAccountName string = 'mysqlltrprodst01${take(uniqueString(resourceGroup().id), 4)}'
param automationAccountName string = 'MySQLLTR-prod-aa-${location}-01'
param userAssignedIdentityName string = 'MySQLLTR-prod-id-${location}-01'
param location string = resourceGroup().location
param backupFileShareName string = 'backup-file-share'
param scriptLocation string = deployment().properties.templateLink.uri

param enableAvmTelemetry bool = true
param tags object?

@description('The private DNS zone must be linked to the virtual network already.')
param fileSharePrivateDnsZoneResourceId string
//param keyVaultPrivateDnsZoneResourceId string
param privateEndpointSubnetResourceId string
@description('Must be delegated to *Microsoft.ContainerInstance/containerGroups*')
param containerInstanceSubnetResourceId string

param mySqlUsername string = 'sqladmin'
@secure()
param mySqlPassword string

param scheduleStartDate string = dateTimeAdd(utcNow(), 'P1D', 'yyyy-MM-dd')
param scheduleStartTimeUtc string = '06:00:00' // 2 AM Eastern Time
param databaseNamesForBackup array = ['redcapdb']
param databaseHostName string

module userAssignedIdentityModule 'br/public:avm/res/managed-identity/user-assigned-identity:0.6.0' = {
  name: 'userAssignedIdentityModule'
  params: {
    name: userAssignedIdentityName
    location: location

    enableTelemetry: enableAvmTelemetry
    tags: tags
  }
}

module automationAccountOuterModule 'automationAccount.bicep' = {
  name: 'automationAccountOuterModule'
  params: {
    automationAccountName: automationAccountName
    containerInstanceSubnetResourceId: containerInstanceSubnetResourceId
    scriptLocation: scriptLocation
    location: location
    scheduleStartDate: scheduleStartDate
    scheduleStartTimeUtc: scheduleStartTimeUtc
    uamiClientId: userAssignedIdentityModule.outputs.clientId
    uamiResourceId: userAssignedIdentityModule.outputs.resourceId
    databaseHostName: databaseHostName
    databaseNamesForBackup: databaseNamesForBackup
    storageAccountName: storageAccountName
    backupFileShareName: backupFileShareName
    containerRegistryLoginServer: containerRegistryModule.outputs.loginServer
    mySqlUsername: mySqlUsername
    mySqlPassword: mySqlPassword
    acrName: containerRegistryModule.outputs.name
    enableAvmTelemetry: enableAvmTelemetry
    tags: tags
  }
}

module storageAccountModule 'br/public:avm/res/storage/storage-account:0.33.0' = {
  name: 'storageAccountModule'
  params: {
    name: storageAccountName
    location: location
    skuName: 'Standard_GRS'
    kind: 'StorageV2'

    supportsHttpsTrafficOnly: true
    // Required to support mounting container volume
    allowSharedKeyAccess: true

    fileServices: {
      shareDeleteRetentionPolicy: {
        enabled: true
        days: 7
      }
      shares: [
        {
          name: backupFileShareName
          accessTier: 'TransactionOptimized'
          shareQuota: 5120
          enabledProtocols: 'SMB'
        }
      ]
    }

    privateEndpoints: [
      {
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: fileSharePrivateDnsZoneResourceId
            }
          ]
        }
        subnetResourceId: privateEndpointSubnetResourceId
        service: 'file'
      }
    ]

    roleAssignments: [
      {
        principalId: userAssignedIdentityModule.outputs.principalId
        // Required role to retrieve storage account keys for mounting the file share in the container instance
        roleDefinitionIdOrName: 'Storage Account Key Operator Service Role'
        principalType: 'ServicePrincipal'
      }
    ]

    enableTelemetry: enableAvmTelemetry
    tags: tags
  }
}

module containerRegistryModule 'br/public:avm/res/container-registry/registry:0.13.0' = {
  name: 'containerRegistryModule'
  params: {
    name: 'mysqlltrprodcr01${take(uniqueString(resourceGroup().id), 4)}'
    location: location
    acrSku: 'Basic'

    // Required for Container Instance to pull the image
    acrAdminUserEnabled: true

    roleAssignmentMode: 'AbacRepositoryPermissions'

    networkRuleBypassAllowedForTasks: true

    roleAssignments: [
      {
        principalId: userAssignedIdentityModule.outputs.principalId
        roleDefinitionIdOrName: 'AcrPull'
        principalType: 'ServicePrincipal'
      }
      {
        principalId: deployer().objectId
        roleDefinitionIdOrName: 'AcrPush'
        principalType: 'User'
      }
    ]

    // TODO: Build the container image
    // tasks: [
    //   {
    //     name: 'BuildTask'
    //   }
    // ]

    enableTelemetry: enableAvmTelemetry
    tags: tags
  }
}

// This must be in a separate module so we can use the .listCredentials() function on the ACR resource,
// which is not available here because the ACR is references as an existing resource.
// module keyVaultOuterModule 'keyVault.bicep' = {
//   name: 'keyVaultOuterModule'
//   params: {
//     acrName: containerRegistryModule.outputs.name
//     location: location
//     keyVaultPrivateDnsZoneResourceId: keyVaultPrivateDnsZoneResourceId
//     privateEndpointSubnetResourceId: privateEndpointSubnetResourceId
//     uamiPrincipalId: userAssignedIdentityModule.outputs.principalId
//     mySqlUsername: mySqlUsername
//     mySqlPassword: mySqlPassword

//     enableAvmTelemetry: enableAvmTelemetry
//     tags: tags
//   }
// }

// Create role assignments on resource group
module resourceGroupRoleAssignmentModule 'br/public:avm/res/authorization/role-assignment/rg-scope:0.1.1' = {
  name: 'resourceGroupRoleAssignmentModule'
  params: {
    principalId: userAssignedIdentityModule.outputs.principalId
    roleDefinitionIdOrName: 'Contributor'
    principalType: 'ServicePrincipal'

    enableTelemetry: enableAvmTelemetry
  }
}
