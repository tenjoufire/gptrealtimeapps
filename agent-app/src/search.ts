import { config } from "./config.js";
import { credential } from "./credential.js";

export interface SearchResult {
  id: string;
  title: string;
  content: string;
  fileName?: string;
  source?: string;
  url?: string;
  score?: number;
}

export interface KnowledgeBaseSearchResponse {
  answer?: string;
  results: SearchResult[];
  activity?: unknown;
}

function buildMockResults(query: string): KnowledgeBaseSearchResponse {
  const results = [
    {
      id: crypto.randomUUID(),
      title: "Mock: パスワード再設定手順",
      content: `検索モック応答です。ユーザーの問い合わせ「${query}」に対して、本人確認後にパスワード再設定リンクを案内してください。`,
      fileName: "password-reset.md",
      source: "password-reset.md",
      url: "https://example.local/mock/password-reset",
      score: 1
    },
    {
      id: crypto.randomUUID(),
      title: "Mock: VPN 接続トラブル",
      content: "VPN 利用時は端末再起動、資格情報の再入力、MFA の再実施を順に確認します。改善しない場合は IT 管理者へエスカレーションします。",
      fileName: "vpn-help.md",
      source: "vpn-help.md",
      url: "https://example.local/mock/vpn-help",
      score: 0.92
    }
  ];

  return {
    answer: results[0]?.content,
    results
  };
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

function asRecord(value: unknown): Record<string, unknown> | undefined {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return undefined;
  }

  return value as Record<string, unknown>;
}

function asString(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function asNumber(value: unknown): number | undefined {
  return typeof value === "number" ? value : undefined;
}

function getNestedString(source: Record<string, unknown> | undefined, keys: string[]): string | undefined {
  if (!source) {
    return undefined;
  }

  for (const key of keys) {
    const value = asString(source[key]);
    if (value) {
      return value;
    }
  }

  return undefined;
}

function extractFileName(value: string | undefined): string | undefined {
  if (!value) {
    return undefined;
  }

  const withoutQuery = value.split(/[?#]/, 1)[0]?.replace(/\\/g, "/");
  const candidate = withoutQuery?.split("/").filter(Boolean).at(-1);

  if (!candidate) {
    return undefined;
  }

  try {
    return decodeURIComponent(candidate);
  } catch {
    return candidate;
  }
}

function getAnswer(payload: Record<string, unknown>): string | undefined {
  const response = Array.isArray(payload.response) ? payload.response : [];
  const textParts = response
    .flatMap((item) => {
      const record = asRecord(item);
      return Array.isArray(record?.content) ? record.content : [];
    })
    .map((item) => getNestedString(asRecord(item), ["text"]))
    .filter((item): item is string => Boolean(item));

  if (textParts.length === 0) {
    return undefined;
  }

  return textParts.join("\n\n");
}

function mapReferenceToResult(reference: Record<string, unknown>, index: number): SearchResult {
  const sourceData =
    asRecord(reference.sourceData) ??
    asRecord(reference.source_data) ??
    asRecord(reference.document) ??
    asRecord(reference.payload);

  const sourcePath =
    getNestedString(reference, ["blobUrl", "blobURL"]) ??
    getNestedString(sourceData, ["source", "metadata_storage_path", "storagePath"]);
  const url =
    getNestedString(reference, ["url", "blobUrl", "blobURL"]) ??
    getNestedString(sourceData, ["url", "metadata_storage_path"]);

  const fileName =
    getNestedString(reference, ["fileName", "filename"]) ??
    getNestedString(sourceData, ["fileName", "filename", "metadata_storage_name", "name"]) ??
    extractFileName(url) ??
    extractFileName(sourcePath);

  const title =
    getNestedString(reference, ["title"]) ??
    fileName ??
    getNestedString(sourceData, ["title", "fileName", "filename", "name", "metadata_storage_name"]) ??
    `Reference ${index + 1}`;

  const content =
    getNestedString(reference, ["content", "snippet", "text", "excerpt"]) ??
    getNestedString(sourceData, ["content", "chunk", "text", "summary", "description"]) ??
    "";

  const source =
    fileName ??
    getNestedString(reference, ["source"]) ??
    sourcePath ??
    getNestedString(reference, ["knowledgeSourceName"]) ??
    getNestedString(sourceData, ["containerName"]);

  const score =
    asNumber(reference.score) ??
    asNumber(reference.rerankerScore) ??
    asNumber(reference.searchScore);

  return {
    id:
      getNestedString(reference, ["referenceId", "reference_id", "id"]) ??
      getNestedString(sourceData, ["id", "chunkId"]) ??
      crypto.randomUUID(),
    title,
    content,
    fileName,
    source,
    url,
    score
  };
}

function mapRetrieveResponse(payload: Record<string, unknown>): KnowledgeBaseSearchResponse {
  const answer = getAnswer(payload);
  const references = Array.isArray(payload.references) ? payload.references : [];
  const results = references
    .map((reference, index) => mapReferenceToResult(asRecord(reference) ?? {}, index))
    .filter((result) => result.content.length > 0 || result.title.length > 0)
    .slice(0, config.azureSearchTopK);

  if (results.length > 0) {
    return {
      answer,
      results,
      activity: payload.activity
    };
  }

  return {
    answer,
    results: [],
    activity: payload.activity
  };
}

function getRequiredSearchConfig(): {
  endpoint: string;
  knowledgeBase: string;
  knowledgeSource: string;
} {
  if (!config.azureSearchEndpoint) {
    throw new Error("Missing required environment variable: AZURE_SEARCH_ENDPOINT");
  }

  if (!config.azureSearchKnowledgeBase) {
    throw new Error("Missing required environment variable: AZURE_SEARCH_KNOWLEDGE_BASE");
  }

  if (!config.azureSearchKnowledgeSource) {
    throw new Error("Missing required environment variable: AZURE_SEARCH_KNOWLEDGE_SOURCE");
  }

  return {
    endpoint: config.azureSearchEndpoint,
    knowledgeBase: config.azureSearchKnowledgeBase,
    knowledgeSource: config.azureSearchKnowledgeSource
  };
}

export async function searchKnowledgeBase(query: string): Promise<KnowledgeBaseSearchResponse> {
  if (config.mockSearch) {
    return buildMockResults(query);
  }

  const { endpoint, knowledgeBase, knowledgeSource } = getRequiredSearchConfig();
  const headers = await getSearchHeaders();
  const knowledgeSourceParams: Record<string, unknown> = {
    knowledgeSourceName: knowledgeSource,
    kind: "searchIndex",
    includeReferences: true,
    includeReferenceSourceData: true,
    alwaysQuerySource: true
  };

  if (typeof config.azureSearchRerankerThreshold === "number") {
    knowledgeSourceParams.rerankerThreshold = config.azureSearchRerankerThreshold;
  }

  const body = {
    messages: [
      {
        role: "user",
        content: [
          {
            type: "text",
            text: query
          }
        ]
      }
    ],
    knowledgeSourceParams: [knowledgeSourceParams],
    includeActivity: true,
    outputMode: "answerSynthesis",
    retrievalReasoningEffort: {
      kind: "low"
    }
  };

  const response = await fetch(
    `${endpoint}/knowledgebases/${knowledgeBase}/retrieve?api-version=${config.azureSearchApiVersion}`,
    {
      method: "POST",
      headers,
      body: JSON.stringify(body)
    }
  );

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Azure AI Search knowledge base request failed: ${response.status} ${errorText}`);
  }

  const payload = asRecord(await response.json());

  if (!payload) {
    throw new Error("Azure AI Search knowledge base response was empty.");
  }

  return mapRetrieveResponse(payload);
}
