import { useEffect, useRef, useState } from "react";

import type { TranscriptEntry } from "../components/TranscriptPanel";

type SessionStatus = "idle" | "connecting" | "connected" | "error";

interface ConnectResponse {
  answerSdp: string;
}

interface RealtimeEvent {
  type: string;
  delta?: string;
  transcript?: string;
  text?: string;
  item?: {
    id?: string;
    content?: Array<{
      transcript?: string;
      text?: string;
    }>;
  };
}

const agentApiBaseUrl = import.meta.env.VITE_AGENT_API_BASE_URL ?? "http://localhost:8080";

function randomId(): string {
  return globalThis.crypto.randomUUID();
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

  function appendEntry(entry: TranscriptEntry): void {
    setEntries((current) => [...current, entry]);
  }

  function upsertAssistantDraft(text: string, isFinal: boolean): void {
    setEntries((current) => {
      const draftId = assistantDraftIdRef.current ?? randomId();
      assistantDraftIdRef.current = isFinal ? null : draftId;

      const index = current.findIndex((item) => item.id === draftId);
      const nextEntry: TranscriptEntry = {
        id: draftId,
        speaker: "assistant",
        text,
        final: isFinal
      };

      if (index === -1) {
        return [...current, nextEntry];
      }

      const copy = [...current];
      copy[index] = nextEntry;
      return copy;
    });
  }

  function handleRealtimeEvent(event: RealtimeEvent): void {
    switch (event.type) {
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
      case "response.output_text.delta":
      case "response.output_audio_transcript.delta": {
        if (event.delta) {
          const previous = entries.find((item) => item.id === assistantDraftIdRef.current)?.text ?? "";
          upsertAssistantDraft(previous + event.delta, false);
        }
        break;
      }
      case "response.output_text.done":
      case "response.output_audio_transcript.done": {
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
