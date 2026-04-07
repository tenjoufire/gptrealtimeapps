#!/usr/bin/env bash

set -euo pipefail

search_endpoint="${SEARCH_ENDPOINT%/}"
openai_endpoint="${OPENAI_ENDPOINT%/}"
knowledge_source_url="${search_endpoint}/knowledgesources/${KNOWLEDGE_SOURCE_NAME}?api-version=${SEARCH_API_VERSION}"
knowledge_base_url="${search_endpoint}/knowledgebases/${KNOWLEDGE_BASE_NAME}?api-version=${SEARCH_API_VERSION}"
storage_connection_string="ResourceId=${STORAGE_RESOURCE_ID};"

az login --identity --username "${AZURE_CLIENT_ID}" --allow-no-subscriptions >/dev/null

put_with_retry() {
  local url="$1"
  local body="$2"
  local attempt=1
  local max_attempts=12

  while true; do
    if output=$(az rest \
      --method put \
      --url "$url" \
      --resource "https://search.azure.com" \
      --headers "Content-Type=application/json" \
      --body "$body" 2>&1); then
      echo "$output"
      return 0
    fi

    if [[ "$attempt" -ge "$max_attempts" ]]; then
      echo "$output" >&2
      return 1
    fi

    echo "Retrying search data-plane request after RBAC propagation delay (attempt ${attempt}/${max_attempts})..." >&2
    attempt=$((attempt + 1))
    sleep 15
  done
}

knowledge_source_body=$(cat <<EOF
{
  "name": "${KNOWLEDGE_SOURCE_NAME}",
  "kind": "azureBlob",
  "description": "Blob-backed knowledge source for the GPT Realtime voice help desk.",
  "azureBlobParameters": {
    "connectionString": "${storage_connection_string}",
    "containerName": "${STORAGE_CONTAINER_NAME}",
    "folderPath": null,
    "isADLSGen2": false,
    "ingestionParameters": {
      "identity": null,
      "disableImageVerbalization": false,
      "chatCompletionModel": {
        "kind": "azureOpenAI",
        "azureOpenAIParameters": {
          "resourceUri": "${openai_endpoint}",
          "deploymentId": "${OPENAI_CHAT_DEPLOYMENT_NAME}",
          "modelName": "${OPENAI_CHAT_MODEL_NAME}"
        }
      },
      "embeddingModel": {
        "kind": "azureOpenAI",
        "azureOpenAIParameters": {
          "resourceUri": "${openai_endpoint}",
          "deploymentId": "${OPENAI_EMBEDDING_DEPLOYMENT_NAME}",
          "modelName": "${OPENAI_EMBEDDING_MODEL_NAME}"
        }
      },
      "contentExtractionMode": "minimal",
      "ingestionSchedule": null,
      "ingestionPermissionOptions": []
    }
  }
}
EOF
)

knowledge_base_body=$(cat <<EOF
{
  "name": "${KNOWLEDGE_BASE_NAME}",
  "description": "Knowledge base for the GPT Realtime voice help desk.",
  "retrievalInstructions": "Use this knowledge source to answer internal help desk questions. If the content is insufficient, clearly say that the answer is not present in the knowledge base.",
  "answerInstructions": "Provide a concise grounded answer in Japanese and keep references available for downstream citation handling.",
  "outputMode": "answerSynthesis",
  "knowledgeSources": [
    {
      "name": "${KNOWLEDGE_SOURCE_NAME}"
    }
  ],
  "models": [
    {
      "kind": "azureOpenAI",
      "azureOpenAIParameters": {
        "resourceUri": "${openai_endpoint}",
        "deploymentId": "${OPENAI_CHAT_DEPLOYMENT_NAME}",
        "modelName": "${OPENAI_CHAT_MODEL_NAME}"
      }
    }
  ],
  "retrievalReasoningEffort": {
    "kind": "low"
  }
}
EOF
)

echo "Upserting Azure AI Search knowledge source ${KNOWLEDGE_SOURCE_NAME}..."
put_with_retry "$knowledge_source_url" "$knowledge_source_body" >/dev/null

echo "Upserting Azure AI Search knowledge base ${KNOWLEDGE_BASE_NAME}..."
put_with_retry "$knowledge_base_url" "$knowledge_base_body" >/dev/null

echo "Knowledge source and knowledge base provisioning completed."