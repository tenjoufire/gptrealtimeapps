import WebSocket from "ws";

import { config } from "./config.js";
import { credential } from "./credential.js";
import { executeTool, realtimeTools } from "./tools.js";

interface ConnectResult {
  answerSdp: string;
  callId?: string;
}

export interface RealtimePreflightResult {
  ok: boolean;
  endpoint: string;
  deployment: string;
  mockSearch: boolean;
}

interface RealtimeFunctionCallEvent {
  type: string;
  name?: string;
  arguments?: string;
  call_id?: string;
  callId?: string;
}

const activeObservers = new Map<string, WebSocket>();

function log(message: string, extra?: unknown): void {
  if (extra) {
    console.log(`[agent-app] ${message}`, extra);
    return;
  }

  console.log(`[agent-app] ${message}`);
}

function buildSessionConfig() {
  return {
    type: "realtime",
    model: config.azureOpenAIRealtimeDeployment,
    instructions: config.azureOpenAIInstructions,
    audio: {
      output: {
        voice: config.azureOpenAIRealtimeVoice
      }
    },
    turn_detection: {
      type: "semantic_vad"
    },
    input_audio_transcription: {
      model: "whisper-1"
    },
    tool_choice: "auto",
    tools: realtimeTools
  };
}

function buildClientSecretSessionConfig() {
  return {
    session: {
      type: "realtime",
      model: config.azureOpenAIRealtimeDeployment
    }
  };
}

async function getOpenAIToken(): Promise<string> {
  const token = await credential.getToken("https://cognitiveservices.azure.com/.default");
  if (!token?.token) {
    throw new Error("Failed to acquire Azure OpenAI access token.");
  }

  return token.token;
}

async function createClientSecret(): Promise<string> {
  const response = await fetch(
    `${config.azureOpenAIEndpoint}/openai/v1/realtime/client_secrets`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${await getOpenAIToken()}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify(buildClientSecretSessionConfig())
    }
  );

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Failed to create client secret: ${response.status} ${body}`);
  }

  const payload = (await response.json()) as { value?: string };
  if (!payload.value) {
    throw new Error("Azure OpenAI did not return an ephemeral client secret.");
  }

  return payload.value;
}

export async function runRealtimePreflight(): Promise<RealtimePreflightResult> {
  await createClientSecret();

  return {
    ok: true,
    endpoint: config.azureOpenAIEndpoint,
    deployment: config.azureOpenAIRealtimeDeployment,
    mockSearch: config.mockSearch
  };
}

function extractCallId(locationHeader: string | null): string | undefined {
  if (!locationHeader) {
    return undefined;
  }

  const parts = locationHeader.split("/");
  return parts.at(-1);
}

async function handleFunctionCall(ws: WebSocket, event: RealtimeFunctionCallEvent): Promise<void> {
  const name = event.name;
  const rawArguments = event.arguments ?? "{}";
  const callId = event.call_id ?? event.callId;

  if (!name || !callId) {
    log("Skipping function call event because name or call_id is missing.", event);
    return;
  }

  const result = await executeTool(name, rawArguments);

  ws.send(
    JSON.stringify({
      type: "conversation.item.create",
      item: {
        type: "function_call_output",
        call_id: callId,
        output: JSON.stringify(result.payload)
      }
    })
  );

  ws.send(
    JSON.stringify({
      type: "response.create"
    })
  );
}

async function onObserverMessage(ws: WebSocket, message: WebSocket.RawData): Promise<void> {
  const text = typeof message === "string" ? message : message.toString();
  const event = JSON.parse(text) as RealtimeFunctionCallEvent;

  if (event.type === "response.function_call_arguments.done") {
    await handleFunctionCall(ws, event);
  }
}

function startObserver(callId: string): void {
  if (activeObservers.has(callId)) {
    return;
  }

  void (async () => {
    const token = await getOpenAIToken();
    const ws = new WebSocket(
      `${config.azureOpenAIEndpoint.replace(/^https/, "wss")}/openai/v1/realtime?call_id=${callId}`,
      {
        headers: {
          Authorization: `Bearer ${token}`
        }
      }
    );

    activeObservers.set(callId, ws);

    ws.on("open", () => {
      log(`Observer connected for call ${callId}`);
      ws.send(
        JSON.stringify({
          type: "session.update",
          session: buildSessionConfig()
        })
      );
    });

    ws.on("message", (message) => {
      void onObserverMessage(ws, message).catch((error) => {
        log(`Observer message handling failed for call ${callId}`, error);
      });
    });

    ws.on("close", () => {
      activeObservers.delete(callId);
      log(`Observer closed for call ${callId}`);
    });

    ws.on("error", (error) => {
      activeObservers.delete(callId);
      log(`Observer error for call ${callId}`, error);
    });
  })().catch((error) => {
    log(`Failed to start observer for call ${callId}`, error);
  });
}

export async function connectRealtimeCall(offerSdp: string): Promise<ConnectResult> {
  const secret = await createClientSecret();
  const response = await fetch(
    `${config.azureOpenAIEndpoint}/openai/v1/realtime/calls?webrtcfilter=on`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${secret}`,
        "Content-Type": "application/sdp"
      },
      body: offerSdp
    }
  );

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`SDP negotiation failed: ${response.status} ${body}`);
  }

  const answerSdp = await response.text();
  const callId = extractCallId(response.headers.get("location"));

  if (callId) {
    startObserver(callId);
  }

  return {
    answerSdp,
    callId
  };
}
