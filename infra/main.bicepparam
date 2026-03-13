using './main.bicep'

param location = 'eastus2'
param prefix = 'gptrealtime'
param env = 'dev'

// Build and push these tags into the provisioned ACR before deployment.
param agentImage = 'agent-app:latest'
param webImage = 'web-ui:latest'

// Tighten this to the web UI URL after the app FQDN is known.
param allowedOrigin = '*'

// Keep this true until the Azure AI Search index schema and data are prepared.
param mockSearch = true
param searchIndexName = 'helpdesk-index'
param knowledgeContainerName = 'knowledge'

param acrSku = 'Standard'
param storageSku = 'Standard_LRS'
param searchSku = 'basic'
param searchReplicaCount = 1
param searchPartitionCount = 1
param openAiSku = 'S0'

param openAiRealtimeDeploymentName = 'gpt-realtime-1.5'
param openAiRealtimeModelName = 'gpt-realtime'
// Replace with the exact model version available in your Azure OpenAI region.
param openAiRealtimeModelVersion = '2026-02-23'
param openAiRealtimeCapacity = 1

param openAiEmbeddingDeploymentName = 'text-embedding-3-large'
param openAiEmbeddingModelName = 'text-embedding-3-large'
// Replace with the exact model version available in your Azure OpenAI region.
param openAiEmbeddingModelVersion = 'REPLACE_ME'
param openAiEmbeddingCapacity = 1

param agentCpu = 1
param agentMemory = '2Gi'
param webCpu = '0.5'
param webMemory = '1Gi'