declare global {
  interface Window {
    __APP_CONFIG__?: {
      VITE_AGENT_API_BASE_URL?: string;
    };
  }
}

function normalizeBaseUrl(raw?: string): string {
  return (raw ?? 'http://localhost:8080').replace(/\/$/, '');
}

export const agentApiBaseUrl = normalizeBaseUrl(
  window.__APP_CONFIG__?.VITE_AGENT_API_BASE_URL ?? import.meta.env.VITE_AGENT_API_BASE_URL
);
