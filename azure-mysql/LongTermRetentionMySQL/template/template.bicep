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
param keyVaultPrivateDnsZoneResourceId string
param privateEndpointSubnetResourceId string
@description('Must be delegated to *Microsoft.ContainerInstance/containerGroups*')
param containerInstanceSubnetResourceId string

@secure()
param mySqlUsername string
@secure()
param mySqlPassword string

module userAssignedIdentityModule 'br/public:avm/res/managed-identity/user-assigned-identity:0.6.0' = {
  name: 'userAssignedIdentityModule'
  params: {
    name: userAssignedIdentityName
    location: location

    enableTelemetry: enableAvmTelemetry
    tags: tags
  }
}

module automationAccountModule 'br/public:avm/res/automation/automation-account:0.19.2' = {
  name: 'automationAccountModule'
  params: {
    name: automationAccountName
    location: location
    skuName: 'Basic'

    runbooks: [
      {
        name: 'BackupMySqlDatabase'
        description: 'Runbook to backup MySQL database to Azure Storage for long-term retention. See https://techcommunity.microsoft.com/blog/adformysql/azure-database-for-mysql-extending-long-term-retention-by-using-containers/3065164'
        type: 'PowerShell72'
        uri: uri(scriptLocation, 'runbook/backupmysql.ps1')
        version: '1.0.0.0'
      }
    ]

    managedIdentities: {
      systemAssigned: true
      userAssignedResourceIds: [
        userAssignedIdentityModule.outputs.resourceId
      ]
    }

    enableTelemetry: enableAvmTelemetry
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

    // tasks: [
    //   {
    //     name: 'BuildTask'
    //   }
    // ]

    enableTelemetry: enableAvmTelemetry
    tags: tags
  }
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
        principalId: userAssignedIdentityModule.outputs.principalId
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
