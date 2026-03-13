import { useRef } from "react";

import { StatusIndicator } from "./components/StatusIndicator";
import { TranscriptPanel } from "./components/TranscriptPanel";
import { useRealtimeSession } from "./hooks/useRealtimeSession";

export default function App() {
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const { status, error, entries, startSession, stopSession, attachAudioElement } = useRealtimeSession();

  return (
    <main className="shell">
      <section className="hero">
        <div className="hero__eyebrow">GPT Realtime 1.5 + Azure AI Search</div>
        <h1>音声ヘルプデスク</h1>
        <p>
          ブラウザから音声で問い合わせると、バックエンドの Agent App が Realtime セッションを監視し、
          Azure AI Search を使ってナレッジベースを検索します。
        </p>

        <div className="hero__controls">
          <StatusIndicator status={status} />
          <button className="button button--primary" onClick={() => void startSession()} disabled={status === "connecting" || status === "connected"}>
            セッション開始
          </button>
          <button className="button button--secondary" onClick={stopSession} disabled={status === "idle"}>
            セッション終了
          </button>
        </div>

        {error ? <p className="hero__error">{error}</p> : null}
      </section>

      <section className="panel-grid">
        <article className="panel panel--transcript">
          <header className="panel__header">
            <h2>Transcript</h2>
            <p>ユーザー音声の文字起こしと、AI 応答のストリームを表示します。</p>
          </header>
          <TranscriptPanel entries={entries} />
        </article>

        <article className="panel panel--audio">
          <header className="panel__header">
            <h2>Audio Output</h2>
            <p>AI の音声は WebRTC のリモートオーディオトラックから再生されます。</p>
          </header>

          <div className="audio-stage">
            <div className="audio-stage__orb" />
            <audio
              controls
              autoPlay
              ref={(node) => {
                audioRef.current = node;
                attachAudioElement(node);
              }}
            />
          </div>
        </article>
      </section>
    </main>
  );
}
