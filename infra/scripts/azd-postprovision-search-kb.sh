#!/usr/bin/env bash

set -euo pipefail

if [[ "${MOCK_SEARCH:-false}" == "true" ]]; then
  echo "Skipping knowledge source provisioning because MOCK_SEARCH=true."
  exit 0
fi

required_vars=(
  SEARCH_ENDPOINT
  SEARCH_API_VERSION
  KNOWLEDGE_SOURCE_NAME
  KNOWLEDGE_BASE_NAME
  STORAGE_RESOURCE_ID
  STORAGE_CONTAINER_NAME
  OPENAI_ENDPOINT
  OPENAI_CHAT_DEPLOYMENT_NAME
  OPENAI_CHAT_MODEL_NAME
  OPENAI_EMBEDDING_DEPLOYMENT_NAME
  OPENAI_EMBEDDING_MODEL_NAME
)

for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "Missing required environment variable: ${var_name}" >&2
    exit 1
  fi
done

bash ./infra/scripts/provision-search-kb.sh