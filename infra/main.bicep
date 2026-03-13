targetScope = 'resourceGroup'

@description('Name of the azd environment.')
param environmentName string

@description('Deployment location for all resources.')
param location string = resourceGroup().location

@description('Set true while Azure AI Search index creation is still pending.')
param mockSearch bool = true

@description('Azure AI Search index name consumed by the agent app.')
param searchIndexName string = 'helpdesk-index'

@description('Blob container used as the knowledge source landing area.')
param knowledgeContainerName string = 'knowledge'

@description('Azure AI Search SKU.')
@allowed([
  'basic'
  'standard'
  'standard2'
  'standard3'
])
param searchSku string = 'basic'

@description('Replica count for Azure AI Search.')
param searchReplicaCount int = 1

@description('Partition count for Azure AI Search.')
param searchPartitionCount int = 1

@description('Azure OpenAI account SKU.')
@allowed([
  'S0'
])
param openAiSku string = 'S0'

@description('Realtime deployment name exposed to the application.')
param openAiRealtimeDeploymentName string = 'gpt-realtime-1.5'

@description('Realtime model name for the Azure OpenAI deployment.')
param openAiRealtimeModelName string

@description('Realtime model version for the Azure OpenAI deployment.')
param openAiRealtimeModelVersion string

@description('Capacity for the realtime deployment.')
param openAiRealtimeCapacity int = 1

@description('Embedding deployment name exposed to the application.')
param openAiEmbeddingDeploymentName string = 'text-embedding-3-large'

@description('Embedding model name for the Azure OpenAI deployment.')
param openAiEmbeddingModelName string

@description('Embedding model version for the Azure OpenAI deployment.')
param openAiEmbeddingModelVersion string

@description('Capacity for the embedding deployment.')
param openAiEmbeddingCapacity int = 1

var resourceToken = uniqueString(subscription().id, resourceGroup().id, location, environmentName)

var tags = {
  Environment: environmentName
}

var logAnalyticsName = 'azlog${resourceToken}'
var appInsightsName = 'azapp${resourceToken}'
var acrName = 'azacr${resourceToken}'
var storageAccountName = 'azst${resourceToken}'
var searchServiceName = 'azsea${resourceToken}'
var openAiAccountName = 'azai${resourceToken}'
var openAiSubdomain = 'azai${resourceToken}'
var managedIdentityName = 'azid${resourceToken}'
var containerEnvName = 'azcae${resourceToken}'
var agentAppName = 'azcaa${resourceToken}'
var webAppName = 'azcaw${resourceToken}'

var acrPullRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
var storageBlobDataReaderRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1')
var searchIndexDataReaderRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '1407120a-92aa-4202-b7e9-c0e197c71c8f')
var openAiUserRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    retentionInDays: 30
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Bluefield'
    WorkspaceResourceId: logAnalytics.id
  }
}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
  tags: tags
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-06-01-preview' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
  }
}

resource acrPullAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, acrPullRoleDefinitionId, managedIdentity.id)
  scope: acr
  properties: {
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: acrPullRoleDefinitionId
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
  properties: {
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource knowledgeContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2024-01-01' = {
  parent: blobService
  name: knowledgeContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource search 'Microsoft.Search/searchServices@2025-02-01-preview' = {
  name: searchServiceName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: searchSku
  }
  properties: {
    authOptions: {
      aadOrApiKey: {
        aadAuthFailureMode: 'http401WithBearerChallenge'
      }
    }
    disableLocalAuth: false
    hostingMode: 'default'
    partitionCount: searchPartitionCount
    publicNetworkAccess: 'Enabled'
    replicaCount: searchReplicaCount
    semanticSearch: 'standard'
  }
}

resource searchToStorageAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, storageBlobDataReaderRoleDefinitionId, search.id)
  scope: storage
  properties: {
    principalId: search.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: storageBlobDataReaderRoleDefinitionId
  }
}

resource openAi 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: openAiAccountName
  location: location
  kind: 'AIServices'
  identity: {
    type: 'SystemAssigned'
  }
  tags: tags
  sku: {
    name: openAiSku
  }
  properties: {
    allowProjectManagement: true
    customSubDomainName: openAiSubdomain
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
    restrictOutboundNetworkAccess: false
  }
}

resource realtimeDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: openAi
  name: openAiRealtimeDeploymentName
  sku: {
    name: 'GlobalStandard'
    capacity: openAiRealtimeCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: openAiRealtimeModelName
      version: openAiRealtimeModelVersion
    }
  }
}

resource embeddingDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: openAi
  name: openAiEmbeddingDeploymentName
  dependsOn: [
    realtimeDeployment
  ]
  sku: {
    name: 'GlobalStandard'
    capacity: openAiEmbeddingCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: openAiEmbeddingModelName
      version: openAiEmbeddingModelVersion
    }
  }
}

resource openAiUserAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openAi.id, openAiUserRoleDefinitionId, managedIdentity.id)
  scope: openAi
  properties: {
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: openAiUserRoleDefinitionId
  }
}

resource searchReaderAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(search.id, searchIndexDataReaderRoleDefinitionId, managedIdentity.id)
  scope: search
  properties: {
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: searchIndexDataReaderRoleDefinitionId
  }
}

resource containerEnv 'Microsoft.App/managedEnvironments@2024-10-02-preview' = {
  name: containerEnvName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    publicNetworkAccess: 'Enabled'
  }
}

resource agentApp 'Microsoft.App/containerApps@2025-01-01' = {
  name: agentAppName
  location: location
  tags: union(tags, {
    'azd-service-name': 'agent-app'
  })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    environmentId: containerEnv.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        allowInsecure: false
        corsPolicy: {
          allowCredentials: false
          allowedOrigins: [
            '*'
          ]
          allowedMethods: [
            '*'
          ]
          allowedHeaders: [
            '*'
          ]
        }
        external: true
        targetPort: 8080
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
        transport: 'auto'
      }
      registries: [
        {
          identity: managedIdentity.id
          server: acr.properties.loginServer
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'agentapp'
          image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
          env: [
            {
              name: 'PORT'
              value: '8080'
            }
            {
              name: 'ALLOWED_ORIGIN'
              value: '*'
            }
            {
              name: 'LOG_LEVEL'
              value: 'info'
            }
            {
              name: 'MOCK_SEARCH'
              value: mockSearch ? 'true' : 'false'
            }
            {
              name: 'AZURE_CLIENT_ID'
              value: managedIdentity.properties.clientId
            }
            {
              name: 'AZURE_OPENAI_ENDPOINT'
              value: openAi.properties.endpoint
            }
            {
              name: 'AZURE_OPENAI_REALTIME_DEPLOYMENT'
              value: openAiRealtimeDeploymentName
            }
            {
              name: 'AZURE_OPENAI_REALTIME_VOICE'
              value: 'coral'
            }
            {
              name: 'AZURE_OPENAI_INSTRUCTIONS'
              value: 'あなたは社内ヘルプデスクの音声アシスタントです。回答は日本語で、必要に応じてナレッジベースを検索してください。'
            }
            {
              name: 'AZURE_OPENAI_EMBEDDING_DEPLOYMENT'
              value: openAiEmbeddingDeploymentName
            }
            {
              name: 'AZURE_SEARCH_ENDPOINT'
              value: 'https://${search.name}.search.windows.net'
            }
            {
              name: 'AZURE_SEARCH_INDEX'
              value: searchIndexName
            }
            {
              name: 'AZURE_SEARCH_API_VERSION'
              value: '2024-07-01'
            }
            {
              name: 'AZURE_SEARCH_VECTOR_FIELD'
              value: 'contentVector'
            }
            {
              name: 'AZURE_SEARCH_SEMANTIC_CONFIGURATION'
              value: 'default'
            }
            {
              name: 'AZURE_SEARCH_TOP_K'
              value: '5'
            }
          ]
          resources: {
            cpu: json('1')
            memory: '2Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 2
      }
    }
  }
  dependsOn: [
    acrPullAssignment
    openAiUserAssignment
    searchReaderAssignment
  ]
}

resource webApp 'Microsoft.App/containerApps@2025-01-01' = {
  name: webAppName
  location: location
  tags: union(tags, {
    'azd-service-name': 'web-ui'
  })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    environmentId: containerEnv.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        allowInsecure: false
        corsPolicy: {
          allowCredentials: false
          allowedOrigins: [
            '*'
          ]
          allowedMethods: [
            '*'
          ]
          allowedHeaders: [
            '*'
          ]
        }
        external: true
        targetPort: 80
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
        transport: 'auto'
      }
      registries: [
        {
          identity: managedIdentity.id
          server: acr.properties.loginServer
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'webui'
          image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
          env: [
            {
              name: 'VITE_AGENT_API_BASE_URL'
              value: 'https://${agentApp.properties.configuration.ingress.fqdn}'
            }
          ]
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 2
      }
    }
  }
  dependsOn: [
    acrPullAssignment
  ]
}

output RESOURCE_GROUP_ID string = resourceGroup().id
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = acr.properties.loginServer
output AZURE_CONTAINER_REGISTRY_NAME string = acr.name
output AGENT_APP_URL string = 'https://${agentApp.properties.configuration.ingress.fqdn}'
output WEB_UI_URL string = 'https://${webApp.properties.configuration.ingress.fqdn}'
output AZURE_OPENAI_ENDPOINT string = openAi.properties.endpoint
output AZURE_SEARCH_ENDPOINT string = 'https://${search.name}.search.windows.net'
output AZURE_STORAGE_ACCOUNT_NAME string = storage.name
output AZURE_KNOWLEDGE_CONTAINER_NAME string = knowledgeContainerName
