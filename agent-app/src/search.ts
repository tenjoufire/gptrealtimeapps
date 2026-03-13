import { config } from "./config.js";
import { credential } from "./credential.js";

export interface SearchResult {
  id: string;
  title: string;
  content: string;
  source?: string;
  url?: string;
  score?: number;
}

function buildMockResults(query: string): SearchResult[] {
  return [
    {
      id: crypto.randomUUID(),
      title: "Mock: パスワード再設定手順",
      content: `検索モック応答です。ユーザーの問い合わせ「${query}」に対して、本人確認後にパスワード再設定リンクを案内してください。`,
      source: "mock-kb",
      url: "https://example.local/mock/password-reset",
      score: 1
    },
    {
      id: crypto.randomUUID(),
      title: "Mock: VPN 接続トラブル",
      content: "VPN 利用時は端末再起動、資格情報の再入力、MFA の再実施を順に確認します。改善しない場合は IT 管理者へエスカレーションします。",
      source: "mock-kb",
      url: "https://example.local/mock/vpn-help",
      score: 0.92
    }
  ];
}

async function getSearchHeaders(): Promise<HeadersInit> {
  const token = await credential.getToken("https://search.azure.com/.default");

  if (!token?.token) {
    throw new Error("Failed to acquire Azure AI Search access token.");
  }

  return {
    Authorization: `Bearer ${token.token}`,
    "Content-Type": "application/json"
  };
}

async function createEmbedding(query: string): Promise<number[] | undefined> {
  if (!config.azureOpenAIEmbeddingDeployment) {
    return undefined;
  }

  const token = await credential.getToken("https://cognitiveservices.azure.com/.default");
  if (!token?.token) {
    throw new Error("Failed to acquire Azure OpenAI access token.");
  }

  const response = await fetch(
    `${config.azureOpenAIEndpoint}/openai/v1/embeddings`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token.token}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        model: config.azureOpenAIEmbeddingDeployment,
        input: query
      })
    }
  );

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Embedding request failed: ${response.status} ${body}`);
  }

  const payload = (await response.json()) as {
    data?: Array<{ embedding?: number[] }>;
  };

  return payload.data?.[0]?.embedding;
}

export async function searchKnowledgeBase(query: string): Promise<SearchResult[]> {
  if (config.mockSearch || !config.azureSearchEndpoint || !config.azureSearchIndex) {
    return buildMockResults(query);
  }

  const headers = await getSearchHeaders();
  const embedding = await createEmbedding(query);

  const body: Record<string, unknown> = {
    count: true,
    search: query,
    queryType: config.azureSearchSemanticConfiguration ? "semantic" : "simple",
    top: config.azureSearchTopK,
    select: "id,title,content,source,url"
  };

  if (config.azureSearchSemanticConfiguration) {
    body.semanticConfiguration = config.azureSearchSemanticConfiguration;
  }

  if (embedding) {
    body.vectorQueries = [
      {
        kind: "vector",
        vector: embedding,
        fields: config.azureSearchVectorField,
        k: config.azureSearchTopK
      }
    ];
  }

  const response = await fetch(
    `${config.azureSearchEndpoint}/indexes/${config.azureSearchIndex}/docs/search?api-version=${config.azureSearchApiVersion}`,
    {
      method: "POST",
      headers,
      body: JSON.stringify(body)
    }
  );

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Azure AI Search request failed: ${response.status} ${errorText}`);
  }

  const payload = (await response.json()) as {
    value?: Array<Record<string, unknown>>;
  };

  return (payload.value ?? []).map((item) => ({
    id: String(item.id ?? crypto.randomUUID()),
    title: String(item.title ?? "Untitled"),
    content: String(item.content ?? ""),
    source: item.source ? String(item.source) : undefined,
    url: item.url ? String(item.url) : undefined,
    score: typeof item["@search.score"] === "number" ? Number(item["@search.score"]) : undefined
  }));
}
