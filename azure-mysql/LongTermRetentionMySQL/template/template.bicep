param storageAccountName string = 'mysqlltrprodst01${take(uniqueString(resourceGroup().id), 4)}'
param automationAccountName string = 'MySQLLTR-prod-aa-${location}-01'
param userAssignedIdentityName string = 'MySQLLTR-prod-id-${location}-01'
param location string = resourceGroup().location
param backupFileShareName string = 'backup-file-share'
param scriptLocation string = deployment().properties.templateLink.uri

param enableAvmTelemetry bool = true
param tags object = {}

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

    enableTelemetry: enableAvmTelemetry
    tags: tags
  }
}
