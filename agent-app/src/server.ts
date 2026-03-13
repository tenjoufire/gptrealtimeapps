import cors from "cors";
import express from "express";

import { config } from "./config.js";
import { connectRealtimeCall, runRealtimePreflight } from "./realtime.js";

interface ConnectRequestBody {
  sdp?: string;
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
