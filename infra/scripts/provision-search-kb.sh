#!/usr/bin/env bash

set -euo pipefail

search_endpoint="${SEARCH_ENDPOINT%/}"
openai_endpoint="${OPENAI_ENDPOINT%/}"
knowledge_source_url="${search_endpoint}/knowledgesources/${KNOWLEDGE_SOURCE_NAME}?api-version=${SEARCH_API_VERSION}"
knowledge_base_url="${search_endpoint}/knowledgebases/${KNOWLEDGE_BASE_NAME}?api-version=${SEARCH_API_VERSION}"
storage_connection_string="ResourceId=${STORAGE_RESOURCE_ID};"
disable_image_verbalization="${SEARCH_DISABLE_IMAGE_VERBALIZATION:-true}"

case "$disable_image_verbalization" in
  true|false)
    ;;
  *)
    echo "SEARCH_DISABLE_IMAGE_VERBALIZATION must be either 'true' or 'false'." >&2
    exit 1
    ;;
esac

if [[ "$disable_image_verbalization" == "true" ]]; then
  chat_completion_model_fragment=''
else
  chat_completion_model_fragment=$(cat <<EOF
,
      "chatCompletionModel": {
        "kind": "azureOpenAI",
        "azureOpenAIParameters": {
          "resourceUri": "${openai_endpoint}",
          "deploymentId": "${OPENAI_CHAT_DEPLOYMENT_NAME}",
          "modelName": "${OPENAI_CHAT_MODEL_NAME}"
        }
      }
EOF
)
fi

if [[ -n "${AZURE_CLIENT_ID:-}" ]]; then
  az login --identity --username "${AZURE_CLIENT_ID}" --allow-no-subscriptions >/dev/null
fi

run_search_rest() {
  local method="$1"
  local url="$2"
  local body="${3:-}"
  local args=(
    az rest
    --only-show-errors
    --method "$method"
    --url "$url"
    --resource "https://search.azure.com"
    --headers "Content-Type=application/json"
  )

  if [[ -n "$body" ]]; then
    args+=(--body "$body")
  fi

  "${args[@]}"
}

request_with_retry() {
  local method="$1"
  local url="$2"
  local body="${3:-}"
  local attempt=1
  local max_attempts=40

  while true; do
    if output=$(run_search_rest "$method" "$url" "$body" 2>&1); then
      echo "$output"
      return 0
    fi

    if [[ "$output" == *"The chat completion model configuration cannot be changed"* ]]; then
      echo "$output" >&2
      return 2
    fi

    if [[ "$method" == "delete" ]] && [[ "$output" == *"was not found"* || "$output" == *"ResourceNotFound"* || "$output" == *"Not Found"* ]]; then
      return 0
    fi

    if [[ "$attempt" -ge "$max_attempts" ]]; then
      echo "$output" >&2
      return 1
    fi

    echo "Retrying search data-plane request after RBAC propagation delay (attempt ${attempt}/${max_attempts})..." >&2
    attempt=$((attempt + 1))
    sleep 20
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
      "disableImageVerbalization": ${disable_image_verbalization}${chat_completion_model_fragment},
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

recreate_knowledge_resources() {
  echo "Deleting Azure AI Search knowledge base ${KNOWLEDGE_BASE_NAME} so the knowledge source can be recreated..."
  request_with_retry delete "$knowledge_base_url" >/dev/null

  echo "Deleting Azure AI Search knowledge source ${KNOWLEDGE_SOURCE_NAME} to apply immutable ingestion changes..."
  request_with_retry delete "$knowledge_source_url" >/dev/null

  echo "Recreating Azure AI Search knowledge source ${KNOWLEDGE_SOURCE_NAME} with SEARCH_DISABLE_IMAGE_VERBALIZATION=${disable_image_verbalization}..."
  request_with_retry put "$knowledge_source_url" "$knowledge_source_body" >/dev/null

  echo "Recreating Azure AI Search knowledge base ${KNOWLEDGE_BASE_NAME}..."
  request_with_retry put "$knowledge_base_url" "$knowledge_base_body" >/dev/null
}

echo "Upserting Azure AI Search knowledge source ${KNOWLEDGE_SOURCE_NAME} with SEARCH_DISABLE_IMAGE_VERBALIZATION=${disable_image_verbalization}..."
if request_with_retry put "$knowledge_source_url" "$knowledge_source_body" >/dev/null; then
  echo "Upserting Azure AI Search knowledge base ${KNOWLEDGE_BASE_NAME}..."
  request_with_retry put "$knowledge_base_url" "$knowledge_base_body" >/dev/null
else
  status=$?

  if [[ "$status" -ne 2 ]]; then
    exit "$status"
  fi

  echo "Search reports the chatCompletionModel configuration is immutable; recreating the knowledge source and knowledge base." >&2
  recreate_knowledge_resources
fi

echo "Knowledge source and knowledge base provisioning completed."