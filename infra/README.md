# Infra

このディレクトリは、音声チャットアプリの Azure 基盤をまとめてデプロイするための Bicep と補助スクリプトです。

## デプロイ対象

- Azure Container Registry
- Azure Storage Account と `knowledge` Blob コンテナ
- Azure AI Search
- Azure AI Foundry project
- Azure AI Search knowledge source / knowledge base を作る deployment script
- Azure AI Services account と 3 つの deployment
- User Assigned Managed Identity
- Azure Container Apps Environment
- `agent-app` / `web-ui` の 2 つの Container Apps
- Log Analytics Workspace
- Application Insights
- 必要な RBAC

## モデル構成

既定値では次の deployment を作成します。

- realtime: `gpt-realtime` / `2025-08-28`
- embedding: `text-embedding-3-large` / `1`
- knowledge base chat: `gpt-4.1-mini` / `2025-04-14`

realtime deployment 名は `gpt-realtime-1.5`、embedding deployment 名は `text-embedding-3-large`、knowledge base chat deployment 名は `gpt-4.1-mini` を使います。

`gpt-realtime-1.5-2026-02-23` は docs 上は利用可能モデルですが、このテンプレートを `eastus2` へ ARM 検証した時点では `DeploymentModelNotSupported` で失敗しました。そのため既定値は `gpt-realtime` / `2025-08-28` にしています。

## 先に確認するパラメータ

`main.parameters.json` または `main.bicepparam` の次の値を必要に応じて更新してください。

- `foundryProjectName`
- `foundrySearchConnectionName`
- `knowledgeSourceName`
- `knowledgeBaseName`
- `openAiRealtimeModelName`
- `openAiRealtimeModelVersion`
- `openAiEmbeddingModelVersion`
- `openAiChatModelName`
- `openAiChatModelVersion`
- `mockSearch`

`mockSearch` は初期値を `false` にしています。Search を使わずアプリだけ立ち上げたい場合のみ `true` に切り替えてください。

## デプロイ手順

1. `azd env new <environment-name>` を実行します。
2. `azd env set AZURE_LOCATION eastus2` を実行します。
3. 必要なら `main.parameters.json` または `main.bicepparam` の値を更新します。
4. `azd up` を実行します。

`azd up` では次を一括実行します。

- Azure リソースの作成
- Foundry project と Search connection の作成
- deployment script による Azure AI Search knowledge source / knowledge base の作成
- ACR remote build
- Container Apps の更新

## Bicep 実行例

```bash
az deployment group create \
  --resource-group <resource-group> \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam
```

## knowledge source と knowledge base について

Azure AI Search の knowledge source / knowledge base は 2025-11-01-preview の data plane API を使って作成します。Bicep では preview data plane object を直接表現しづらいため、`scripts/provision-search-kb.sh` を deployment script として呼び出しています。

この deployment script は次を行います。

- Blob knowledge source を PUT で idempotent に作成または更新
- knowledge base を PUT で idempotent に作成または更新
- Search RBAC 反映待ちに備えて `az rest` をリトライ

## ドキュメント投入時の注意

ストレージアカウントと Blob コンテナはこのテンプレートで作成されるため、初回 `azd up` 時にコンテナが空のことがあります。その場合はドキュメントをアップロードした後に再度 provisioning を流してください。

```bash
azd provision
```

これで knowledge source / knowledge base の定義を同名で再適用できます。

## 補足

- Storage は shared key を無効化し、Search と deployment script は Microsoft Entra ベースでアクセスします。
- Search service 自身の system-assigned identity に `Storage Blob Data Reader` と `Cognitive Services OpenAI User` を割り当てています。
- Foundry project には system-assigned identity を付与し、Azure AI Search へ `Search Index Data Reader` を割り当てています。
- `allowedOrigin` は初期 bring-up 用に `*` を許容しています。本番では web UI の URL に固定してください。