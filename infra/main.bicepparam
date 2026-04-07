using './main.bicep'

param environmentName = 'gptrealtime-dev'
param location = 'eastus2'

param mockSearch = false
param knowledgeContainerName = 'knowledge'
param foundryProjectName = 'voice-helpdesk'
param foundrySearchConnectionName = 'helpdesk-search'
param knowledgeSourceName = 'helpdesk-blob-ks'
param knowledgeBaseName = 'helpdesk-kb'

param searchSku = 'basic'
param searchReplicaCount = 1
param searchPartitionCount = 1
param openAiSku = 'S0'

param openAiRealtimeDeploymentName = 'gpt-realtime-1.5'
// The gpt-realtime-1.5 control-plane deployment currently fails ARM validation in this subscription/region.
param openAiRealtimeModelName = 'gpt-realtime'
param openAiRealtimeModelVersion = '2025-08-28'
param openAiRealtimeCapacity = 1

param openAiEmbeddingDeploymentName = 'text-embedding-3-large'
param openAiEmbeddingModelName = 'text-embedding-3-large'
param openAiEmbeddingModelVersion = '1'
param openAiEmbeddingCapacity = 1

param openAiChatDeploymentName = 'gpt-4.1-mini'
param openAiChatModelName = 'gpt-4.1-mini'
param openAiChatModelVersion = '2025-04-14'
param openAiChatCapacity = 1