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

param mySqlUsername string = 'sqladmin'
@secure()
param mySqlPassword string

param scheduleStartDate string = dateTimeAdd(utcNow(), 'P1D', 'yyyy-MM-dd')
param scheduleStartTime string = '02:00:00'
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

var runBookName = 'BackupMySqlDatabase'
var scheduleName = 'WeeklyOnSundaySchedule'

module automationAccountModule 'br/public:avm/res/automation/automation-account:0.19.2' = {
  name: 'automationAccountModule'
  params: {
    name: automationAccountName
    location: location
    skuName: 'Basic'

    runbooks: [
      {
        name: runBookName
        description: 'Runbook to backup MySQL database to Azure Storage for long-term retention. See https://techcommunity.microsoft.com/blog/adformysql/azure-database-for-mysql-extending-long-term-retention-by-using-containers/3065164'
        type: 'PowerShell72'
        uri: uri(scriptLocation, 'runbook/backupmysql.ps1')
        version: '1.0.0.0'
      }
    ]

    schedules: [
      {
        name: scheduleName
        description: 'Schedule to run every week at 2 AM UTC.'
        frequency: 'Week'
        interval: 1
        startTime: '${scheduleStartDate}T${scheduleStartTime}'
        timeZone: 'America/New_York'
        advancedSchedule: {
          weekDays: ['Sunday']
        }
      }
    ]

    jobSchedules: [
      {
        description: 'Schedule to run the ${runBookName} runbook based on the ${scheduleName} schedule.'
        runbookName: runBookName
        scheduleName: scheduleName

        parameters: {
          // TODO: List all
          ManagedIdentityClientId: userAssignedIdentityModule.outputs.clientId
          ContainerResourceGroupName: resourceGroup().name
          DatabaseHostName: databaseHostName
          // TODO: Remove secrets from here
          MySqlUsername: mySqlUsername
          MySqlPassword: mySqlPassword
          // End secrets
          DatabaseNames: join(databaseNamesForBackup, ' ')
          StorageAccountName: storageAccountModule.outputs.name
          BackupFileShareName: backupFileShareName
          ContainerInstanceSubnetResourceId: containerInstanceSubnetResourceId
          ContainerRegistryUrl: containerRegistryModule.outputs.loginServer
          Location: location
        }
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
module keyVaultOuterModule 'keyVault.bicep' = {
  name: 'keyVaultOuterModule'
  params: {
    acrName: containerRegistryModule.outputs.name
    location: location
    keyVaultPrivateDnsZoneResourceId: keyVaultPrivateDnsZoneResourceId
    privateEndpointSubnetResourceId: privateEndpointSubnetResourceId
    uamiPrincipalId: userAssignedIdentityModule.outputs.principalId
    mySqlUsername: mySqlUsername
    mySqlPassword: mySqlPassword

    enableAvmTelemetry: enableAvmTelemetry
    tags: tags
  }
}

// TODO: Create role assignments on resource group
