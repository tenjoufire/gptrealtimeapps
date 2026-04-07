targetScope = 'resourceGroup'

@description('Name of the azd environment.')
param environmentName string

@description('Deployment location for all resources.')
param location string = resourceGroup().location

@description('Set true to return mock knowledge base responses from the agent app.')
param mockSearch bool = true

@description('Blob container used as the knowledge source landing area.')
param knowledgeContainerName string = 'knowledge'

@description('Azure AI Foundry project name.')
param foundryProjectName string = 'voice-helpdesk'

@description('Azure AI Foundry connection name for Azure AI Search.')
param foundrySearchConnectionName string = 'helpdesk-search'

@description('Knowledge source name created in Azure AI Search.')
param knowledgeSourceName string = 'helpdesk-blob-ks'

@description('Knowledge base name created in Azure AI Search.')
param knowledgeBaseName string = 'helpdesk-kb'

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

@description('Chat deployment used by Azure AI Search knowledge source ingestion and answer synthesis.')
param openAiChatDeploymentName string = 'gpt-4.1-mini'

@description('Chat model name for the Azure OpenAI deployment used by the knowledge base.')
param openAiChatModelName string

@description('Chat model version for the Azure OpenAI deployment used by the knowledge base.')
param openAiChatModelVersion string

@description('Capacity for the chat deployment.')
param openAiChatCapacity int = 1

var resourceToken = uniqueString(subscription().id, resourceGroup().id, location, environmentName)
var searchKnowledgeApiVersion = '2025-11-01-preview'

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
var knowledgeProvisionerIdentityName = 'azidp${resourceToken}'
var containerEnvName = 'azcae${resourceToken}'
var agentAppName = 'azcaa${resourceToken}'
var webAppName = 'azcaw${resourceToken}'
var knowledgeProvisioningScriptName = 'azdks${resourceToken}'

var acrPullRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
var storageBlobDataReaderRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1')
var searchIndexDataReaderRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '1407120a-92aa-4202-b7e9-c0e197c71c8f')
var searchServiceContributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7ca78c08-252a-4471-8644-bb5ff32d4ba0')
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
    allowSharedKeyAccess: false
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
    disableLocalAuth: true
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

resource chatDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: openAi
  name: openAiChatDeploymentName
  dependsOn: [
    embeddingDeployment
  ]
  sku: {
    name: 'GlobalStandard'
    capacity: openAiChatCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: openAiChatModelName
      version: openAiChatModelVersion
    }
  }
}

resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: openAi
  name: foundryProjectName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: 'GPT Realtime Help Desk'
    description: 'Foundry project for the GPT Realtime voice help desk and its Azure AI Search knowledge base.'
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

resource searchToOpenAiAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openAi.id, openAiUserRoleDefinitionId, search.id)
  scope: openAi
  properties: {
    principalId: search.identity.principalId
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

resource foundryProjectSearchReaderAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(search.id, searchIndexDataReaderRoleDefinitionId, foundryProject.id)
  scope: search
  properties: {
    principalId: foundryProject.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: searchIndexDataReaderRoleDefinitionId
  }
}

resource knowledgeProvisionerIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: knowledgeProvisionerIdentityName
  location: location
  tags: tags
}

resource knowledgeProvisionerSearchContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(search.id, searchServiceContributorRoleDefinitionId, knowledgeProvisionerIdentity.id)
  scope: search
  properties: {
    principalId: knowledgeProvisionerIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: searchServiceContributorRoleDefinitionId
  }
}

resource foundrySearchConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' = {
  parent: foundryProject
  name: foundrySearchConnectionName
  properties: {
    category: 'CognitiveSearch'
    target: 'https://${search.name}.search.windows.net'
    authType: 'AAD'
    isSharedToAll: true
    useWorkspaceManagedIdentity: true
  }
  dependsOn: [
    foundryProjectSearchReaderAssignment
  ]
}

resource knowledgeBaseProvisioningScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: knowledgeProvisioningScriptName
  location: location
  tags: tags
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${knowledgeProvisionerIdentity.id}': {}
    }
  }
  properties: {
    azCliVersion: '2.64.0'
    cleanupPreference: 'OnSuccess'
    containerSettings: {
      containerGroupName: 'azdks-${resourceToken}'
    }
    environmentVariables: [
      {
        name: 'AZURE_CLIENT_ID'
        value: knowledgeProvisionerIdentity.properties.clientId
      }
      {
        name: 'SEARCH_ENDPOINT'
        value: 'https://${search.name}.search.windows.net'
      }
      {
        name: 'SEARCH_API_VERSION'
        value: searchKnowledgeApiVersion
      }
      {
        name: 'KNOWLEDGE_SOURCE_NAME'
        value: knowledgeSourceName
      }
      {
        name: 'KNOWLEDGE_BASE_NAME'
        value: knowledgeBaseName
      }
      {
        name: 'STORAGE_RESOURCE_ID'
        value: storage.id
      }
      {
        name: 'STORAGE_CONTAINER_NAME'
        value: knowledgeContainerName
      }
      {
        name: 'OPENAI_ENDPOINT'
        value: openAi.properties.endpoint
      }
      {
        name: 'OPENAI_CHAT_DEPLOYMENT_NAME'
        value: openAiChatDeploymentName
      }
      {
        name: 'OPENAI_CHAT_MODEL_NAME'
        value: openAiChatModelName
      }
      {
        name: 'OPENAI_EMBEDDING_DEPLOYMENT_NAME'
        value: openAiEmbeddingDeploymentName
      }
      {
        name: 'OPENAI_EMBEDDING_MODEL_NAME'
        value: openAiEmbeddingModelName
      }
    ]
    forceUpdateTag: uniqueString(knowledgeSourceName, knowledgeBaseName, openAiChatDeploymentName, openAiEmbeddingDeploymentName, knowledgeContainerName, searchKnowledgeApiVersion)
    retentionInterval: 'P1D'
    scriptContent: loadTextContent('scripts/provision-search-kb.sh')
    timeout: 'PT30M'
  }
  dependsOn: [
    chatDeployment
    embeddingDeployment
    foundrySearchConnection
    knowledgeContainer
    knowledgeProvisionerSearchContributorAssignment
    searchToOpenAiAssignment
    searchToStorageAssignment
  ]
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
              name: 'AZURE_SEARCH_ENDPOINT'
              value: 'https://${search.name}.search.windows.net'
            }
            {
              name: 'AZURE_SEARCH_KNOWLEDGE_BASE'
              value: knowledgeBaseName
            }
            {
              name: 'AZURE_SEARCH_KNOWLEDGE_SOURCE'
              value: knowledgeSourceName
            }
            {
              name: 'AZURE_SEARCH_API_VERSION'
              value: searchKnowledgeApiVersion
            }
            {
              name: 'AZURE_SEARCH_TOP_K'
              value: '5'
            }
            {
              name: 'AZURE_SEARCH_RERANKER_THRESHOLD'
              value: '2.5'
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
    knowledgeBaseProvisioningScript
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
output AZURE_AI_FOUNDRY_PROJECT_NAME string = foundryProject.name
output AZURE_AI_FOUNDRY_PROJECT_ID string = foundryProject.id
output AZURE_SEARCH_KNOWLEDGE_SOURCE_NAME string = knowledgeSourceName
output AZURE_SEARCH_KNOWLEDGE_BASE_NAME string = knowledgeBaseName
output AZURE_STORAGE_ACCOUNT_NAME string = storage.name
output AZURE_KNOWLEDGE_CONTAINER_NAME string = knowledgeContainerName
