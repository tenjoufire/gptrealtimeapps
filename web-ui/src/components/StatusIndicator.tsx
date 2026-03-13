interface StatusIndicatorProps {
  status: "idle" | "connecting" | "connected" | "error";
}

const labels: Record<StatusIndicatorProps["status"], string> = {
  idle: "待機中",
  connecting: "接続中",
  connected: "会話中",
  error: "エラー"
};

export function StatusIndicator({ status }: StatusIndicatorProps) {
  return (
    <div className={`status-pill status-pill--${status}`}>
      <span className="status-pill__dot" />
      <span>{labels[status]}</span>
    </div>
  );
}
