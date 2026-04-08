import cors from "cors";
import express from "express";

import { config } from "./config.js";
import { connectRealtimeCall, runRealtimePreflight } from "./realtime.js";
import { searchKnowledgeBase } from "./search.js";

interface ConnectRequestBody {
  sdp?: string;
}

const defaultSearchProbeQuery = "冷蔵ケースの基準温度と点検頻度を確認したい";

function getSingleQueryValue(value: unknown): string | undefined {
  if (typeof value === "string" && value.trim().length > 0) {
    return value.trim();
  }

  if (Array.isArray(value)) {
    const firstString = value.find(
      (item): item is string => typeof item === "string" && item.trim().length > 0
    );

    if (firstString) {
      return firstString.trim();
    }
  }

  return undefined;
}

const app = express();

app.use(
  cors({
    origin: config.allowedOrigin
  })
);
app.use(express.json({ limit: "2mb" }));

app.get("/health", (_request, response) => {
  response.json({
    ok: true,
    service: "agent-app",
    mockSearch: config.mockSearch
  });
});

app.get("/api/realtime/preflight", async (_request, response) => {
  try {
    const result = await runRealtimePreflight();
    response.json(result);
  } catch (error) {
    response.status(500).json({
      ok: false,
      error: error instanceof Error ? error.message : "Realtime preflight failed."
    });
  }
});

app.get("/api/search/probe", async (request, response) => {
  const query = getSingleQueryValue(request.query.query) ?? defaultSearchProbeQuery;

  try {
    const result = await searchKnowledgeBase(query);
    response.json({
      ok: true,
      mockSearch: config.mockSearch,
      query,
      search: {
        endpoint: config.azureSearchEndpoint,
        knowledgeBase: config.azureSearchKnowledgeBase,
        knowledgeSource: config.azureSearchKnowledgeSource,
        apiVersion: config.azureSearchApiVersion,
        topK: config.azureSearchTopK,
        rerankerThreshold: config.azureSearchRerankerThreshold
      },
      answer: result.answer,
      results: result.results,
      resultCount: result.results.length,
      activity: result.activity
    });
  } catch (error) {
    response.status(500).json({
      ok: false,
      mockSearch: config.mockSearch,
      query,
      search: {
        endpoint: config.azureSearchEndpoint,
        knowledgeBase: config.azureSearchKnowledgeBase,
        knowledgeSource: config.azureSearchKnowledgeSource,
        apiVersion: config.azureSearchApiVersion
      },
      error: error instanceof Error ? error.message : "Search probe failed."
    });
  }
});

app.post("/api/realtime/connect", async (request, response) => {
  const body = request.body as ConnectRequestBody;

  if (!body.sdp) {
    response.status(400).json({ error: "Request body must include 'sdp'." });
    return;
  }

  try {
    const result = await connectRealtimeCall(body.sdp);
    response.json(result);
  } catch (error) {
    response.status(500).json({
      error: error instanceof Error ? error.message : "Failed to connect realtime session."
    });
  }
});

app.listen(config.port, () => {
  console.log(`[agent-app] listening on port ${config.port}`);
});
