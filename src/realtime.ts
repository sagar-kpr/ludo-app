export type RealtimeEvent = { type: string; [key: string]: unknown };
export function connectRealtime(onEvent: (event: RealtimeEvent) => void, onStatus: (connected: boolean) => void) {
  const socket = new WebSocket(import.meta.env.VITE_REALTIME_URL || 'ws://localhost:8787');
  socket.onopen = () => onStatus(true); socket.onclose = () => onStatus(false); socket.onerror = () => onStatus(false);
  socket.onmessage = (message) => { try { onEvent(JSON.parse(message.data) as RealtimeEvent); } catch { /* ignore malformed events */ } };
  return { send: (event: unknown) => { if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify(event)); }, close: () => socket.close() };
}
