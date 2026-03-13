export interface TranscriptEntry {
  id: string;
  speaker: "user" | "assistant" | "system";
  text: string;
  final: boolean;
}

interface TranscriptPanelProps {
  entries: TranscriptEntry[];
}

export function TranscriptPanel({ entries }: TranscriptPanelProps) {
  if (entries.length === 0) {
    return (
      <div className="transcript transcript--empty">
        <p>まだ会話は始まっていません。マイクを有効にしてセッションを開始してください。</p>
      </div>
    );
  }

  return (
    <div className="transcript">
      {entries.map((entry) => (
        <article key={entry.id} className={`transcript__item transcript__item--${entry.speaker}`}>
          <header className="transcript__meta">
            <span>{entry.speaker === "user" ? "あなた" : entry.speaker === "assistant" ? "ヘルプデスク" : "system"}</span>
            <span>{entry.final ? "final" : "streaming"}</span>
          </header>
          <p>{entry.text}</p>
        </article>
      ))}
    </div>
  );
}
