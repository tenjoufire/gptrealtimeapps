import { useEffect, useRef, useState } from "react";

import type { TranscriptEntry } from "../components/TranscriptPanel";
import { agentApiBaseUrl } from "../config";

type SessionStatus = "idle" | "connecting" | "connected" | "error";

interface ConnectResponse {
  answerSdp: string;
}

interface RealtimeEvent {
  type: string;
  delta?: string;
  transcript?: string;
  text?: string;
  arguments?: string;
  call_id?: string;
  callId?: string;
  item?: {
    id?: string;
    type?: string;
    name?: string;
    arguments?: string;
    output?: string;
    call_id?: string;
    callId?: string;
    content?: Array<{
      transcript?: string;
      text?: string;
    }>;
  };
}

interface SearchSource {
  fileName?: string;
  title?: string;
  source?: string;
  url?: string;
  score?: number;
}

interface SearchToolPayload {
  query?: string;
  error?: string;
  results?: SearchSource[];
}

function randomId(): string {
  return globalThis.crypto.randomUUID();
}

function parseJson<T>(value: string | undefined): T | undefined {
  if (!value) {
    return undefined;
  }

  try {
    return JSON.parse(value) as T;
  } catch {
    return undefined;
  }
}

function formatSearchSources(payload: SearchToolPayload | undefined): string {
  if (!payload) {
    return "ナレッジベース検索を実行しました。\n情報ソースを解析できませんでした。";
  }

  const lines = ["ナレッジベース検索を実行しました。"];

  if (payload.query) {
    lines.push(`クエリ: ${payload.query}`);
  }

  if (payload.error) {
    lines.push(`検索エラー: ${payload.error}`);
    return lines.join("\n");
  }

  const results = Array.isArray(payload.results) ? payload.results : [];
  const fileNames = [...new Set(results.map((result) => result.fileName).filter((value): value is string => Boolean(value)))];

  if (fileNames.length === 0) {
    lines.push("情報ソース: 該当なし");
    return lines.join("\n");
  }

  lines.push("情報ソース (Blob ファイル名):");

  fileNames.forEach((fileName, index) => {
    lines.push(`${index + 1}. ${fileName}`);
  });

  return lines.join("\n");
}

export function useRealtimeSession() {
  const [status, setStatus] = useState<SessionStatus>("idle");
  const [error, setError] = useState<string | null>(null);
  const [entries, setEntries] = useState<TranscriptEntry[]>([]);

  const peerConnectionRef = useRef<RTCPeerConnection | null>(null);
  const dataChannelRef = useRef<RTCDataChannel | null>(null);
  const localStreamRef = useRef<MediaStream | null>(null);
  const remoteAudioRef = useRef<HTMLAudioElement | null>(null);
  const assistantDraftIdRef = useRef<string | null>(null);
  const assistantDraftTextRef = useRef("");
  const searchEntryIdsRef = useRef(new Map<string, string>());

  function appendEntry(entry: TranscriptEntry): void {
    setEntries((current) => [...current, entry]);
  }

  function upsertEntry(entry: TranscriptEntry): void {
    setEntries((current) => {
      const index = current.findIndex((item) => item.id === entry.id);

      if (index === -1) {
        return [...current, entry];
      }

      const copy = [...current];
      copy[index] = entry;
      return copy;
    });
  }

  function upsertAssistantDraft(text: string, isFinal: boolean): void {
    const draftId = assistantDraftIdRef.current ?? randomId();
    assistantDraftIdRef.current = isFinal ? null : draftId;
    assistantDraftTextRef.current = isFinal ? "" : text;

    upsertEntry({
      id: draftId,
      speaker: "assistant",
      text,
      final: isFinal
    });
  }

  function upsertSearchEntry(callId: string, text: string, isFinal: boolean): void {
    const entryId = searchEntryIdsRef.current.get(callId) ?? randomId();

    searchEntryIdsRef.current.set(callId, entryId);

    upsertEntry({
      id: entryId,
      speaker: "system",
      text,
      final: isFinal
    });

    if (isFinal) {
      searchEntryIdsRef.current.delete(callId);
    }
  }

  function startKnowledgeBaseSearch(callId: string, rawArguments: string | undefined): void {
    const payload = parseJson<{ query?: string }>(rawArguments);
    const text = payload?.query
      ? `ナレッジベースを検索しています。\nクエリ: ${payload.query}`
      : "ナレッジベースを検索しています。";

    upsertSearchEntry(callId, text, false);
  }

  function finalizeKnowledgeBaseSearch(callId: string, rawOutput: string | undefined): void {
    const payload = parseJson<SearchToolPayload>(rawOutput);
    upsertSearchEntry(callId, formatSearchSources(payload), true);
  }

  function handleRealtimeEvent(event: RealtimeEvent): void {
    switch (event.type) {
      case "conversation.item.created": {
        if (event.item?.type === "function_call" && event.item.name === "search_knowledge_base") {
          const callId = event.item.call_id ?? event.item.callId;
          if (callId) {
            startKnowledgeBaseSearch(callId, event.item.arguments ?? event.arguments);
          }
        }

        if (event.item?.type === "function_call_output") {
          const callId = event.item.call_id ?? event.item.callId ?? event.call_id ?? event.callId;
          if (callId) {
            finalizeKnowledgeBaseSearch(callId, event.item.output);
          }
        }
        break;
      }
      case "conversation.item.input_audio_transcription.completed": {
        const text =
          event.transcript ?? event.item?.content?.[0]?.transcript ?? event.item?.content?.[0]?.text ?? "";
        if (text) {
          appendEntry({
            id: event.item?.id ?? randomId(),
            speaker: "user",
            text,
            final: true
          });
        }
        break;
      }
      case "response.function_call_arguments.done": {
        const callId = event.call_id ?? event.callId;
        if (callId) {
          startKnowledgeBaseSearch(callId, event.arguments);
        }
        break;
      }
      case "response.output_text.delta":
      case "response.output_audio_transcript.delta":
      case "response.text.delta":
      case "response.audio_transcript.delta": {
        if (event.delta) {
          upsertAssistantDraft(`${assistantDraftTextRef.current}${event.delta}`, false);
        }
        break;
      }
      case "response.output_text.done":
      case "response.output_audio_transcript.done":
      case "response.text.done":
      case "response.audio_transcript.done": {
        const finalText = event.text ?? event.transcript;
        if (finalText) {
          upsertAssistantDraft(finalText, true);
        }
        break;
      }
      default:
        break;
    }
  }

  async function startSession(): Promise<void> {
    setError(null);
    setStatus("connecting");

    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true
        }
      });

      localStreamRef.current = stream;

      const peerConnection = new RTCPeerConnection();
      peerConnectionRef.current = peerConnection;

      peerConnection.ontrack = (event) => {
        const audioElement = remoteAudioRef.current;
        if (audioElement && event.streams[0]) {
          audioElement.srcObject = event.streams[0];
          void audioElement.play().catch(() => undefined);
        }
      };

      peerConnection.onconnectionstatechange = () => {
        if (peerConnection.connectionState === "connected") {
          setStatus("connected");
        }

        if (["failed", "disconnected", "closed"].includes(peerConnection.connectionState)) {
          setStatus(peerConnection.connectionState === "closed" ? "idle" : "error");
        }
      };

      for (const track of stream.getTracks()) {
        peerConnection.addTrack(track, stream);
      }

      const dataChannel = peerConnection.createDataChannel("realtime-channel");
      dataChannelRef.current = dataChannel;

      dataChannel.addEventListener("message", (message) => {
        const event = JSON.parse(String(message.data)) as RealtimeEvent;
        handleRealtimeEvent(event);
      });

      const offer = await peerConnection.createOffer();
      await peerConnection.setLocalDescription(offer);

      const response = await fetch(`${agentApiBaseUrl}/api/realtime/connect`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify({ sdp: offer.sdp })
      });

      if (!response.ok) {
        throw new Error(await response.text());
      }

      const payload = (await response.json()) as ConnectResponse;
      await peerConnection.setRemoteDescription({
        type: "answer",
        sdp: payload.answerSdp
      });
    } catch (sessionError) {
      setStatus("error");
      setError(sessionError instanceof Error ? sessionError.message : "セッション開始に失敗しました。");
      stopSession();
    }
  }

  function stopSession(): void {
    dataChannelRef.current?.close();
    dataChannelRef.current = null;

    peerConnectionRef.current?.close();
    peerConnectionRef.current = null;

    localStreamRef.current?.getTracks().forEach((track) => track.stop());
    localStreamRef.current = null;

    if (remoteAudioRef.current) {
      remoteAudioRef.current.srcObject = null;
    }

    assistantDraftIdRef.current = null;
    assistantDraftTextRef.current = "";
    searchEntryIdsRef.current.clear();
    setStatus("idle");
  }

  useEffect(() => stopSession, []);

  return {
    status,
    error,
    entries,
    startSession,
    stopSession,
    attachAudioElement: (element: HTMLAudioElement | null) => {
      remoteAudioRef.current = element;
    }
  };
}
