import "dotenv/config";

export interface AppConfig {
  port: number;
  allowedOrigin: string;
  logLevel: string;
  azureClientId?: string;
  azureOpenAIEndpoint: string;
  azureOpenAIRealtimeDeployment: string;
  azureOpenAIRealtimeVoice: string;
  azureOpenAIInstructions: string;
  mockSearch: boolean;
  azureSearchEndpoint?: string;
  azureSearchKnowledgeBase?: string;
  azureSearchKnowledgeSource?: string;
  azureSearchApiVersion: string;
  azureSearchTopK: number;
  azureSearchRerankerThreshold?: number;
}

function getRequired(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function getNumber(name: string, fallback: number): number {
  const raw = process.env[name];
  if (!raw) {
    return fallback;
  }

  const value = Number(raw);
  if (Number.isNaN(value)) {
    throw new Error(`Environment variable ${name} must be a number.`);
  }

  return value;
}

function getBoolean(name: string, fallback: boolean): boolean {
  const raw = process.env[name];
  if (!raw) {
    return fallback;
  }

  return ["1", "true", "yes", "on"].includes(raw.toLowerCase());
}

function normalizeEndpoint(raw: string): string {
  return raw.replace(/\/$/, "");
}

function getOptional(name: string): string | undefined {
  const value = process.env[name];
  return value && value.length > 0 ? value : undefined;
}

function getOptionalEndpoint(name: string): string | undefined {
  const value = getOptional(name);
  return value ? normalizeEndpoint(value) : undefined;
}

const mockSearch = getBoolean("MOCK_SEARCH", false);

export const config: AppConfig = {
  port: getNumber("PORT", 8080),
  allowedOrigin: process.env.ALLOWED_ORIGIN ?? "http://localhost:5173",
  logLevel: process.env.LOG_LEVEL ?? "info",
  azureClientId: process.env.AZURE_CLIENT_ID,
  azureOpenAIEndpoint: normalizeEndpoint(getRequired("AZURE_OPENAI_ENDPOINT")),
  azureOpenAIRealtimeDeployment: getRequired("AZURE_OPENAI_REALTIME_DEPLOYMENT"),
  azureOpenAIRealtimeVoice: process.env.AZURE_OPENAI_REALTIME_VOICE ?? "coral",
  azureOpenAIInstructions:
    process.env.AZURE_OPENAI_INSTRUCTIONS ??
    "あなたは社内ヘルプデスクの音声アシスタントです。回答は日本語で、必要に応じてナレッジベースを検索してください。",
  mockSearch,
  azureSearchEndpoint: getOptionalEndpoint("AZURE_SEARCH_ENDPOINT"),
  azureSearchKnowledgeBase: getOptional("AZURE_SEARCH_KNOWLEDGE_BASE"),
  azureSearchKnowledgeSource: getOptional("AZURE_SEARCH_KNOWLEDGE_SOURCE"),
  azureSearchApiVersion: process.env.AZURE_SEARCH_API_VERSION ?? "2025-11-01-preview",
  azureSearchTopK: getNumber("AZURE_SEARCH_TOP_K", 5),
  azureSearchRerankerThreshold: getOptional("AZURE_SEARCH_RERANKER_THRESHOLD")
    ? getNumber("AZURE_SEARCH_RERANKER_THRESHOLD", 0)
    : undefined
};
