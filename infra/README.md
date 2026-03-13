# Infra

このディレクトリは、次の Azure リソースをまとめてデプロイするための Bicep です。

- Azure Container Registry
- Azure Blob Storage と knowledge コンテナー
- Azure AI Search
- Azure OpenAI
- Log Analytics Workspace
- Application Insights
- User Assigned Managed Identity
- Azure Container Apps Environment
- Agent App / Web UI の 2 つの Container Apps
- 必要な RBAC

## 先に埋める値

main.bicepparam で次の値を必ず更新してください。

- openAiRealtimeModelVersion
- openAiEmbeddingModelVersion
- agentImage
- webImage

OpenAI の deployment 名は既定値で次を使っています。

- gpt-realtime-1.5
- text-embedding-3-large

ただし model version はリージョンと提供状況に依存するため、プレースホルダーのままではデプロイできません。

## デプロイ手順

1. ACR と Agent App を先に使える状態にするため、まず agent イメージを build します。
2. Bicep を実行してインフラを作成します。
3. agentAppUrl の出力を使って web-ui を build し直します。
4. webImage を更新してもう一度 Bicep を実行します。

## 例: ACR build

最初の 1 回目は agent イメージだけでも構いません。

```bash
az acr build -r <acr-name> -t agent-app:latest ./agent-app
```

web-ui は Vite の build 時に API URL を埋め込む必要があります。agentAppUrl がわかった後で build してください。

```bash
az acr build \
  -r <acr-name> \
  -t web-ui:latest \
  --build-arg VITE_AGENT_API_BASE_URL=https://<agent-app-fqdn> \
  ./web-ui
```

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