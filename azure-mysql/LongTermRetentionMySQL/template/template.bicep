param storageAccounts_ltrmysqlbackup_name string = 'saltr${uniqueString(resourceGroup().id)}'
param automationAccounts_aamysqlltr_name string = 'aamysqlltr'
param userAssignedIdentities_umimysqlltr_name string = 'umimysqlltr'
param location string = resourceGroup().location
param backupfileshare string = 'backupfileshare'
param scriptLocation string = deployment().properties.templateLink.uri

resource userAssignedIdentities_umimysqlltr_name_resource 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: userAssignedIdentities_umimysqlltr_name
  location: location
}

resource automationAccounts_aamysqlltr_name_resource 'Microsoft.Automation/automationAccounts@2021-06-22' = {
  name: automationAccounts_aamysqlltr_name
  location: location
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentities_umimysqlltr_name_resource.id}': {}
    }
  }
  properties: {
    sku: {
      name: 'Basic'
    }
    encryption: {
      keySource: 'Microsoft.Automation'
      identity: {}
    }
  }
}

resource automationAccounts_aamysqlltr_name_backupmysqldb 'Microsoft.Automation/automationAccounts/runbooks@2019-06-01' = {
  parent: automationAccounts_aamysqlltr_name_resource
  name: 'backupmysqldb'
  location: location
  properties: {
    logVerbose: false
    logProgress: false
    logActivityTrace: 0
    runbookType: 'PowerShell'
    publishContentLink: {
      uri: uri(scriptLocation, 'runbook/backupmysql.ps1')
      version: '1.0.0.0'
    }
  }
}

resource storageAccounts_ltrmysqlbackup_name_resource 'Microsoft.Storage/storageAccounts@2021-06-01' = {
  name: storageAccounts_ltrmysqlbackup_name
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_0'
    allowBlobPublicAccess: true
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: 'Cool'
  }
}

resource Microsoft_Storage_storageAccounts_fileServices_storageAccounts_ltrmysqlbackup_name_default 'Microsoft.Storage/storageAccounts/fileServices@2021-06-01' = {
  parent: storageAccounts_ltrmysqlbackup_name_resource
  name: 'default'
  properties: {
    shareDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource storageAccounts_ltrmysqlbackup_name_default_backupfileshare 'Microsoft.Storage/storageAccounts/fileServices/shares@2021-06-01' = {
  parent: Microsoft_Storage_storageAccounts_fileServices_storageAccounts_ltrmysqlbackup_name_default
  name: backupfileshare
  properties: {
    accessTier: 'TransactionOptimized'
    shareQuota: 5120
    enabledProtocols: 'SMB'
  }
}
