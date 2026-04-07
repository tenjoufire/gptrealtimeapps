# GPT Realtime 1.5 音声ヘルプデスク — 設計メモ

## 概要

このアプリは GPT Realtime を使った音声ヘルプデスクです。ブラウザは WebRTC で Azure OpenAI Realtime deployment と接続し、バックエンドは observer WebSocket で tool call を処理します。ナレッジ取得は Azure AI Search の knowledge base retrieve API に一本化しています。

## 現在のアーキテクチャ

```text
Browser
  -> web-ui (React + Vite)
  -> agent-app (Express + TypeScript)
      -> Azure OpenAI resource endpoint
         - gpt-realtime
         - text-embedding-3-large
         - gpt-4.1-mini
      -> Azure AI Search knowledge base
         - knowledge source: Blob container
         - knowledge base: answer synthesis + references
      -> Azure AI Foundry project
         - Azure AI Search connection (AAD)
```

## 主要な設計判断

### 1. 音声経路は WebRTC + SDP Proxy のまま維持

- ブラウザは Azure OpenAI resource endpoint と直接 WebRTC 接続します。
- `agent-app` は `client_secrets` と `realtime/calls` を使って SDP を中継します。
- これにより低レイテンシを維持しつつ、ephemeral secret をブラウザへ直接渡しません。

### 2. Foundry project は接続管理とガバナンスに使用

- Azure AI Services アカウント配下に Foundry project を作成します。
- Foundry project から Azure AI Search へ AAD connection を張ります。
- Realtime API 自体は Foundry project endpoint ではなく Azure OpenAI resource endpoint を使います。

### 3. 検索は direct index query から knowledge base retrieve へ移行

- `agent-app` の `search_knowledge_base` ツールは Azure AI Search knowledge base の `retrieve` API を呼びます。
- `knowledgeSourceParams` で references と sourceData を返し、tool output に answer と references を入れます。
- knowledge base 側は `answerSynthesis` と `retrievalReasoningEffort: low` を使います。

### 4. Blob knowledge source は deployment script で作成

- knowledge source / knowledge base は preview の data plane object なので、Bicep から deployment script を呼んで作成します。
- deployment script は idempotent な PUT を使い、RBAC 伝播待ちのためにリトライします。
- ストレージ接続は shared key ではなく `ResourceId=...;` 形式を使います。

## 運用上の注意

- 初回 `azd up` 時に Blob コンテナが空なら、knowledge source は空の状態で作成されます。
- ドキュメントをアップロードした後に `azd provision` を再実行して knowledge source / knowledge base を再適用してください。
- `MOCK_SEARCH=true` を有効にすると backend は Search を呼ばずモック応答を返します。

## モデル既定値

- realtime: `gpt-realtime` / `2025-08-28`
- embedding: `text-embedding-3-large` / `1`
- knowledge base chat: `gpt-4.1-mini` / `2025-04-14`
- Blob Storage にサンプルドキュメントのアップロード
- Indexer + Skillset の設定

### フェーズ 3: Azure デプロイ
- Azure Container Apps へのデプロイ
- Managed Identity の設定
- Bicep テンプレート作成

## 9. ディレクトリ構成（全体）

```
gptrealtimeapps/
├── agent-app/              # バックエンド (Node.js + Express + TypeScript)
│   ├── src/
│   │   ├── server.ts
│   │   ├── realtime.ts
│   │   ├── tools.ts
│   │   └── search.ts
│   ├── package.json
│   ├── tsconfig.json
│   ├── Dockerfile
│   └── .env.example
├── web-ui/                 # フロントエンド (React + Vite + TypeScript)
│   ├── src/
│   │   ├── App.tsx
│   │   ├── components/
│   │   ├── hooks/
│   │   └── main.tsx
│   ├── index.html
│   ├── package.json
│   ├── tsconfig.json
│   ├── vite.config.ts
│   └── Dockerfile
├── plan.md                 # この計画書
└── README.md
```

## 10. 参照ドキュメント

| ドキュメント | URL |
|-------------|-----|
| GPT Realtime API 概要 | https://learn.microsoft.com/azure/foundry/openai/how-to/realtime-audio |
| Realtime API via WebRTC (GA) | https://learn.microsoft.com/azure/foundry/openai/how-to/realtime-audio-webrtc |
| Realtime API via WebSocket | https://learn.microsoft.com/azure/foundry/openai/how-to/realtime-audio-websockets |
| Realtime API リファレンス | https://learn.microsoft.com/azure/foundry/openai/realtime-audio-reference |
| Azure AI Search RAG 概要 | https://learn.microsoft.com/azure/search/retrieval-augmented-generation-overview |
| Azure Container Apps 概要 | https://learn.microsoft.com/azure/container-apps/ |

## 11. 未決事項 / 検討ポイント

- [ ] ヘルプデスクのドメイン（社内IT、製品サポート等）に応じた system prompt の調整
- [ ] AI Search のインデックス設計の詳細化（カテゴリ、タグなど）
- [ ] 音声の言語設定（日本語のみ or 多言語対応）
- [ ] セッションタイムアウトの設定値
- [ ] 同時接続数の見積もりとスケーリング設定
- [ ] ログ収集と会話履歴の永続化方針
- [ ] エラーハンドリング方針（AI Search ダウン時のフォールバック等）
