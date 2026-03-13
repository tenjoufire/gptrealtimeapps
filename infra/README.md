# Infra

このディレクトリは、次の Azure リソースをまとめてデプロイするための Bicep です。

- Azure Container Registry
- Azure Blob Storage と knowledge コンテナー
- Azure AI Search
- Azure AI Foundry resource
- Log Analytics Workspace
- Application Insights
- User Assigned Managed Identity
- Azure Container Apps Environment
- Agent App / Web UI の 2 つの Container Apps
- 必要な RBAC

## 先に埋める値

main.bicepparam で次の値を必要に応じて更新してください。

- openAiRealtimeModelName
- openAiRealtimeModelVersion
- openAiEmbeddingModelVersion

OpenAI の deployment 名は既定値で次を使っています。

- gpt-realtime-1.5
- text-embedding-3-large

既定値では realtime に `gpt-realtime` / `2025-08-28`、embedding に `text-embedding-3-large` / `1` を使っています。`gpt-realtime-1.5-2026-02-23` は docs 上の利用可能モデルですが、このテンプレートを `eastus2` へ ARM 検証した時点では `DeploymentModelNotSupported` で失敗しました。

## デプロイ手順

1. `azd env new <environment-name>` を実行します。
2. `azd env set AZURE_LOCATION eastus2` を実行します。
3. 必要なら main.parameters.json または main.bicepparam の OpenAI model 設定を更新します。
4. `azd up` を実行します。

`azd` が ACR remote build と Container Apps 更新までまとめて実行します。

## Bicep 実行例

```bash
az deployment group create \
  --resource-group <resource-group> \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam
```

## 補足

- このテンプレートは Azure AI Search のサービス本体までは作成しますが、インデックス定義やインデクサーまでは作成しません。
- main.bicepparam の mockSearch は初期値を true にしています。Search インデックスの準備後に false に切り替えてください。
- allowedOrigin は初期 bring-up 用に * を許容しています。本番では web UI の URL に固定してください。