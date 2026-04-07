import { searchKnowledgeBase } from "./search.js";

export const realtimeTools = [
  {
    type: "function",
    name: "search_knowledge_base",
    description: "ヘルプデスク用ナレッジベースを検索し、回答に必要な情報を取得します。",
    parameters: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description: "検索に使う自然言語クエリ"
        }
      },
      required: ["query"]
    }
  }
] as const;

export interface ToolExecutionResult {
  ok: boolean;
  payload: unknown;
}

export async function executeTool(name: string, rawArguments: string): Promise<ToolExecutionResult> {
  if (name !== "search_knowledge_base") {
    return {
      ok: false,
      payload: {
        error: `Unsupported tool: ${name}`
      }
    };
  }

  let parsed: { query?: string };

  try {
    parsed = JSON.parse(rawArguments) as { query?: string };
  } catch {
    return {
      ok: false,
      payload: {
        error: "Tool arguments must be valid JSON."
      }
    };
  }

  if (!parsed.query) {
    return {
      ok: false,
      payload: {
        error: "Tool argument 'query' is required."
      }
    };
  }

  try {
    const results = await searchKnowledgeBase(parsed.query);
    return {
      ok: true,
      payload: {
        query: parsed.query,
        answer: results.answer,
        results: results.results.map((item) => ({
          title: item.title,
          content: item.content,
          source: item.source,
          url: item.url,
          score: item.score
        }))
      }
    };
  } catch (error) {
    return {
      ok: false,
      payload: {
        error: error instanceof Error ? error.message : "Tool execution failed."
      }
    };
  }
}
