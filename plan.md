# GPT Realtime 1.5 音声ヘルプデスク — 実装計画

## 1. システム概要

GPT Realtime 1.5 を利用し、ユーザーが音声でヘルプデスクに問い合わせ、ナレッジベース (Azure AI Search) を検索して回答する音声対話アプリケーション。

### アーキテクチャ構成図

```
┌────────────────────┐
│  GPT Realtime 1.5  │
│  (Azure OpenAI)    │
└──────┬─────────────┘
       │ WebRTC (音声)
       │
┌──────▼─────────────┐    WebSocket (observer)    ┌──────────────────────────┐
│     Web UI         │◄──── token / SDP proxy ────►│  Agent App               │
│  (Node.js+React)   │                             │  (Azure Container Apps)  │
└────────────────────┘                             └──────┬───────────────────┘
                                                          │ function call 実行
                                                   ┌──────▼───────────────────┐
                                                   │  Azure AI Search         │
                                                   │  (Knowledge Base)        │
                                                   └──────┬───────────────────┘
                                                          │ Indexer
                                                   ┌──────▼───────────────────┐
                                                   │  Azure Blob Storage      │
                                                   │  (Knowledge Source)      │
                                                   └──────────────────────────┘
```

## 2. 通信方式の選定

### 調査結果（Microsoft Docs）

| プロトコル | 用途 | レイテンシ | 推奨シナリオ |
|-----------|------|-----------|-------------|
| **WebRTC** | クライアントサイドアプリ | ~50-100ms | Web/モバイルアプリ (**推奨**) |
| WebSocket | サーバー間通信 | ~100-300ms | バックエンド処理、バッチ |
| SIP | テレフォニー | 可変 | コールセンター、IVR |

> 参照: https://learn.microsoft.com/azure/foundry/openai/how-to/realtime-audio-webrtc

### 採用方式: WebRTC + SDP Proxy + WebSocket Observer

**理由**: 
- WebRTC がクライアントアプリでは最も低レイテンシで推奨される
- Agent App が SDP ネゴシエーションを Proxy することで、ephemeral token がブラウザに渡らずセキュア
- WebSocket Observer パターンでセッションを監視し、tool call を処理可能

**通信フロー**:
1. ブラウザが Agent App の `/connect` エンドポイントに SDP Offer を送信
2. Agent App が Azure OpenAI から ephemeral token を取得し、SDP ネゴシエーションを Proxy
3. SDP Answer をブラウザに返却 → WebRTC 接続確立（音声ストリーム直通）
4. Agent App が Location ヘッダーから WebSocket Observer 接続を確立
5. モデルが tool call を発行した場合、Observer WebSocket で検知し、AI Search を呼び出して結果を返却

## 3. 使用モデルとAPI

### モデル
- **gpt-realtime-1.5-2026-02-23** (version 2026-02-23)
- デプロイリージョン: East US 2 または Sweden Central (Global deployment)

### API バージョン
- `2025-08-28` (GA)

### エンドポイント
| 用途 | URL |
|------|-----|
| Ephemeral Token 取得 | `https://{resource}.openai.azure.com/openai/v1/realtime/client_secrets` |
| WebRTC SDP ネゴシエーション | `https://{resource}.openai.azure.com/openai/v1/realtime/calls` |
| WebSocket Observer | `wss://{resource}.openai.azure.com/openai/v1/realtime?call_id={call_id}` |

> 参照: https://learn.microsoft.com/azure/foundry/openai/how-to/realtime-audio-webrtc

### セッション設定

```json
{
  "session": {
    "type": "realtime",
    "model": "<deployment-name>",
    "instructions": "あなたはヘルプデスクのアシスタントです。ユーザーの質問にナレッジベースを検索して回答してください。日本語で対応してください。",
    "audio": {
      "output": {
        "voice": "coral"
      }
    },
    "tools": [
      {
        "type": "function",
        "name": "search_knowledge_base",
        "description": "ナレッジベースを検索してヘルプデスクの質問に回答するための情報を取得します",
        "parameters": {
          "type": "object",
          "properties": {
            "query": {
              "type": "string",
              "description": "検索クエリ"
            }
          },
          "required": ["query"]
        }
      }
    ],
    "turn_detection": {
      "type": "semantic_vad"
    },
    "input_audio_transcription": {
      "model": "whisper-1"
    }
  }
}
```

> 参照: https://learn.microsoft.com/azure/foundry/openai/how-to/realtime-audio#session-configuration

## 4. アプリケーション構成

### 4.1 Agent App（バックエンド — Node.js / Express）

Azure Container Apps にデプロイするバックエンドサーバー。

```
agent-app/
├── src/
│   ├── server.ts           # Express サーバー + ルーティング
│   ├── realtime.ts         # Azure OpenAI Realtime API 連携
│   │                        (ephemeral token 取得, SDP proxy, WebSocket observer)
│   ├── tools.ts            # Tool call ハンドラー (search_knowledge_base 等)
│   └── search.ts           # Azure AI Search クライアント
├── package.json
├── tsconfig.json
├── Dockerfile
└── .env.example
```

**主要エンドポイント**:
| エンドポイント | メソッド | 説明 |
|---------------|---------|------|
| `/connect` | POST | SDP Offer を受け取り、SDP ネゴシエーションを Proxy |
| `/health` | GET | ヘルスチェック |

**主要技術**:
- **Express.js** (TypeScript) — HTTP サーバー
- **@azure/identity** — DefaultAzureCredential による認証
- **@azure/search-documents** — AI Search クライアント
- **ws** — WebSocket Observer 接続

**WebSocket Observer によるツール呼び出しフロー**:
1. WebSocket Observer がモデルからの `response.function_call_arguments.done` イベントを受信
2. `search_knowledge_base` ツールの引数をパース
3. Azure AI Search に対してハイブリッド検索（キーワード + ベクトル）を実行
4. `conversation.item.create` でツール結果をセッションに送信
5. `response.create` でモデルの応答生成を再開

### 4.2 Web UI（フロントエンド — React + Vite）

```
web-ui/
├── src/
│   ├── App.tsx             # メインアプリケーション
│   ├── components/
│   │   ├── AudioSession.tsx    # WebRTC セッション管理
│   │   ├── TranscriptPanel.tsx # 会話トランスクリプト表示
│   │   └── StatusIndicator.tsx # 接続状態表示
│   ├── hooks/
│   │   └── useRealtimeSession.ts # WebRTC セッション管理 hooks
│   └── main.tsx
├── index.html
├── package.json
├── tsconfig.json
├── vite.config.ts
└── Dockerfile
```

**主要機能**:
- マイク入力の WebRTC 音声ストリーミング
- AIからの音声応答のリアルタイム再生
- DataChannel 経由でのトランスクリプト表示（ユーザー音声の文字起こし + AI応答テキスト）
- セッション開始/終了の制御 UI
- 接続状態のインジケーター表示

**WebRTC 接続フロー**:
1. `RTCPeerConnection` を作成
2. マイクアクセスを取得し、audio track を追加
3. DataChannel `realtime-channel` を作成
4. SDP Offer を生成し、Agent App の `/connect` に POST
5. SDP Answer を受け取り、RemoteDescription にセット
6. DataChannel の `message` イベントでトランスクリプトを受信・表示

> 注: SDP Proxy 方式（`/connect` エンドポイント使用）では `webrtcfilter=on` パラメータにより、DataChannel メッセージが以下に制限される:
> - `input_audio_buffer.speech_started` / `speech_stopped`
> - `conversation.item.input_audio_transcription.completed`
> - `response.output_audio_transcript.delta` / `done`

## 5. Azure AI Search 連携

### 検索方式
- **ハイブリッド検索**（キーワード + ベクトル検索 + セマンティックランキング）を採用
- ベクトル検索のための Embedding は Azure OpenAI `text-embedding-3-large` を使用

### インデックス設計

```json
{
  "name": "helpdesk-index",
  "fields": [
    { "name": "id", "type": "Edm.String", "key": true },
    { "name": "title", "type": "Edm.String", "searchable": true },
    { "name": "content", "type": "Edm.String", "searchable": true },
    { "name": "category", "type": "Edm.String", "filterable": true, "facetable": true },
    { "name": "contentVector", "type": "Collection(Edm.Single)", "searchable": true,
      "dimensions": 3072, "vectorSearchProfile": "default-profile" }
  ]
}
```

### データパイプライン
1. Blob Storage にナレッジドキュメント（PDF/Markdown等）をアップロード
2. AI Search Indexer がドキュメントをチャンキング + ベクトル化
3. Skillset で Azure OpenAI Embedding を実行
4. インデックスにドキュメントチャンクを格納

> 参照: https://learn.microsoft.com/azure/search/retrieval-augmented-generation-overview

## 6. セキュリティ

| 項目 | 方式 |
|------|------|
| Azure OpenAI 認証 | DefaultAzureCredential (Managed Identity) |
| AI Search 認証 | DefaultAzureCredential (Managed Identity) |
| Ephemeral Token | Agent App 内部でのみ使用（ブラウザに非公開） |
| SDP ネゴシエーション | Agent App が Proxy（ephemeral token がクライアントに漏れない） |
| CORS | Agent App で Web UI のオリジンのみ許可 |
| HTTPS | Azure Container Apps のデフォルト TLS |

## 7. 技術スタック

| レイヤー | 技術 |
|---------|------|
| フロントエンド | React 19 + TypeScript + Vite |
| バックエンド | Node.js + Express + TypeScript |
| 音声通信 | WebRTC (GA Protocol) |
| AI モデル | gpt-realtime-1.5-2026-02-23 |
| ナレッジ検索 | Azure AI Search (ハイブリッド検索) |
| ドキュメント格納 | Azure Blob Storage |
| ホスティング | Azure Container Apps |
| 認証 | Azure Managed Identity (DefaultAzureCredential) |
| IaC | Bicep (将来) |

## 8. 開発方針

### フェーズ 1: 基本実装（今回のスコープ）
1. **Agent App**: Express サーバー、SDP Proxy、WebSocket Observer、AI Search 連携
2. **Web UI**: React アプリ、WebRTC セッション管理、トランスクリプト表示
3. **ローカル開発**: Docker Compose でローカル実行可能な構成

### フェーズ 2: ナレッジベース構築
- AI Search インデックス作成
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
