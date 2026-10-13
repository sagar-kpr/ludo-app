import 'dotenv/config';
import { randomBytes, randomInt } from 'node:crypto';
import { createServer } from 'node:http';
import { WebSocketServer, WebSocket } from 'ws';
import { autoMoveToken, createGame, moveToken, rollDice, startGame, restartGame, removePlayer, type Color, type GameState, type Player } from '../../../packages/game-engine/src/index';
import { STEP_MS } from '../../../packages/game-engine/src/motion';
import { DICE_ROLL_MS } from '../../../packages/shared/src/dice';
import { persistChat, persistRoom, persistenceEnabled } from './persistence';
import { expireTurn } from './turn-clock';

type ClientMessage = { type: 'PING' } | { type: 'SYNC_STATE' } | { type: 'CREATE_ROOM'; name: string } | { type: 'JOIN_ROOM'; code: string; name: string } | { type: 'START_GAME' } | { type: 'RESTART_GAME' } | { type: 'ROLL_DICE' } | { type: 'MOVE_TOKEN'; tokenId: string } | { type: 'CHAT'; text: string } | { type: 'SEND_STICKER'; targetPlayerId: string; sticker: string };
type Client = { socket: WebSocket; playerId: string; sessionToken: string; roomCode?: string; disconnectTimer?: ReturnType<typeof setTimeout> };
type Room = { code: string; players: Player[]; state: GameState; clients: Map<string, Client>; createdAt: number; busyUntil: number; turnDeadline?: number };
const configuredTurnMs = Number(process.env.TURN_TIMEOUT_MS || 60000);
const turnDurationMs = Number.isFinite(configuredTurnMs) ? Math.max(1000, Math.min(120000, configuredTurnMs)) : 60000;
const rooms = new Map<string, Room>();
const sessions = new Map<string, Client>();
const reconnectGraceMs = Math.max(500, Number(process.env.RECONNECT_GRACE_MS) || 90000);
// The first two players occupy diagonal corners; later joins fill the others.
const colors: Color[] = ['coral', 'mint', 'sun', 'violet'];
const id = (prefix: string) => `${prefix}_${randomBytes(8).toString('hex')}`;
const code = () => `${randomBytes(2).toString('hex').toUpperCase()}-${randomBytes(2).toString('hex').toUpperCase()}`;
const send = (socket: WebSocket, data: unknown) => { if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify(data)); };
const publish = (room: Room, data: unknown) => room.clients.forEach((client) => send(client.socket, data));
const state = (room: Room) => publish(room, { type: 'STATE', roomCode: room.code, state: room.state, players: room.players, serverTime: Date.now(), turnDeadline: room.turnDeadline || 0, turnDurationMs });
function syncState(client: Client) {
  const room = client.roomCode ? rooms.get(client.roomCode) : undefined;
  if (room) send(client.socket, { type: 'STATE', roomCode: room.code, state: room.state, players: room.players, serverTime: Date.now(), turnDeadline: room.turnDeadline || 0, turnDurationMs, recovered: true });
}
function resetClock(room: Room) {
  room.turnDeadline = room.state.phase === 'lobby' || room.state.phase === 'finished' ? 0 : Math.max(Date.now(), room.busyUntil) + turnDurationMs;
}
function expireRoom(room: Room) {
  if (!room.turnDeadline || Date.now() < room.turnDeadline || Date.now() < room.busyUntil) return false;
  room.state = expireTurn(room.state);
  resetClock(room);
  state(room);
  return true;
}
setInterval(() => { for (const room of rooms.values()) if (room.clients.size) expireRoom(room); },100).unref();
const fail = (socket: WebSocket, message: string) => send(socket, { type: 'ERROR', message });
const stickers = new Set(['PARTY','CLAP','LOVE','LAUGH','FIRE','COOL','GIFT','TROPHY','HAMMER','BOOM','CROWN','CLOWN','PUNCH','KISS','TOMATO','EGG']);

function createRoom(client: Client, name: string) {
  if (client.roomCode) return fail(client.socket, 'You already belong to a room.');
  const player: Player = { id: client.playerId, name: name.trim().slice(0, 18) || 'Guest', color: colors[0], ready: true };
  const room: Room = { code: code(), players: [player], state: createGame([player]), clients: new Map([[client.playerId, client]]), createdAt: Date.now(), busyUntil: 0 };
  client.roomCode = room.code; rooms.set(room.code, room); void persistRoom(room.code, room.players, room.state); send(client.socket, { type: 'ROOM_CREATED', roomCode: room.code, playerId: client.playerId }); state(room);
}
function joinRoom(client: Client, value: string, name: string) {
  if (client.roomCode) return fail(client.socket, 'You already belong to a room.');
  const room = rooms.get(value.toUpperCase());
  if (!room) return fail(client.socket, 'Room not found. Check the invite code.');
  if (room.players.length >= 4) return fail(client.socket, 'This room is full.');
  if (room.state.phase !== 'lobby') return fail(client.socket, 'This match has already started.');
  const player: Player = { id: client.playerId, name: name.trim().slice(0, 18) || 'Guest', color: colors.find(color => !room.players.some(player => player.color === color))!, ready: true };
  room.players.push(player); room.state = { ...createGame(room.players), version: room.state.version + 1 }; room.clients.set(client.playerId, client); client.roomCode = room.code; void persistRoom(room.code, room.players, room.state); send(client.socket, { type: 'ROOM_JOINED', roomCode: room.code, playerId: client.playerId }); state(room);
}
function applyMove(room: Room, tokenId: string, automatic = false, presentationMs = DICE_ROLL_MS) {
  const previous = room.state;
  const next = moveToken(previous, tokenId);
  if (next === previous) return false;
  const from = previous.tokens.find((t) => t.id === tokenId)!.position;
  const to = next.tokens.find((t) => t.id === tokenId)!.position;
  const captured = next.tokens.filter((t) => t.position === 0 && previous.tokens.find((p) => p.id === t.id)!.position > 0).map((t) => t.id);
  room.state = next;
  const durationMs = (from === 0 ? 1 : to-from)*STEP_MS;
  const delayMs = automatic ? presentationMs : 0;
  room.busyUntil = Date.now()+delayMs+durationMs;
  resetClock(room);
  publish(room, { type: 'TOKEN_MOVED', tokenId, from, to, captured, automatic, durationMs, delayMs, version: next.version });
  state(room);
  return true;
}
function handle(client: Client, message: ClientMessage) {
  if (message.type === 'PING') { send(client.socket, { type: 'PONG', serverTime: Date.now() }); return; }
  if (message.type === 'SYNC_STATE') { syncState(client); return; }
  if (message.type === 'CREATE_ROOM') return createRoom(client, message.name);
  if (message.type === 'JOIN_ROOM') return joinRoom(client, message.code, message.name);
  if (!client.roomCode) return fail(client.socket, 'Join a room first.');
  const room = rooms.get(client.roomCode); if (!room) return fail(client.socket, 'Room expired.');
  if (message.type === 'RESTART_GAME') {
    if (room.players.length < 2) return fail(client.socket, 'At least two players are required.');
    if (room.players[0].id !== client.playerId) return fail(client.socket, 'Only the host can restart the match.');
    if (room.state.phase !== 'finished') return fail(client.socket, 'Finish the match before restarting.');
    if (Date.now() < room.busyUntil) return fail(client.socket, 'Wait for the final move to finish.');
    room.state = restartGame(room.state);
    room.busyUntil = 0;
    resetClock(room);
    void persistRoom(room.code, room.players, room.state);
    return state(room);
  }
  if ((message.type === 'ROLL_DICE' || message.type === 'MOVE_TOKEN') && expireRoom(room)) return fail(client.socket, 'Your turn expired.');
  if ((message.type === 'ROLL_DICE' || message.type === 'MOVE_TOKEN') && Date.now() < room.busyUntil) return fail(client.socket, 'Wait for the dice or token animation to finish.');
  if (message.type === 'START_GAME') {
    if (room.players[0].id !== client.playerId) return fail(client.socket, 'Only the host can start the match.');
    if (room.players.length < 2) return fail(client.socket, 'At least two players are required.');
    if (room.state.phase !== 'lobby') return fail(client.socket, 'This match has already started.');
    room.state = startGame(room.state); resetClock(room); return state(room);
  }
  if (message.type === 'ROLL_DICE') {
    if (room.state.currentPlayer !== client.playerId) return fail(client.socket, 'It is not your turn.');
    const value = randomInt(1, 7);
    const next = rollDice(room.state, () => (value - 1) / 6);
    if (next === room.state) return fail(client.socket, 'Dice cannot be rolled right now.');
    room.state = next;
    const presentationMs = DICE_ROLL_MS;
    room.busyUntil = Date.now()+presentationMs;
    resetClock(room);
    const automatic = autoMoveToken(next);
    publish(room, { type: 'DICE_ROLLED', value, playerId: client.playerId, color: room.players.find((player) => player.id === client.playerId)!.color, skipped: next.phase === 'rolling', automatic: Boolean(automatic), version: next.version });
    if (automatic) { applyMove(room, automatic.id, true, presentationMs); return; }
    return state(room);
  }
  if (message.type === 'MOVE_TOKEN') {
    if (room.state.currentPlayer !== client.playerId) return fail(client.socket, 'It is not your turn.');
    if (!applyMove(room, message.tokenId)) fail(client.socket, 'That token cannot move.');
    return;
  }
  if (message.type === 'CHAT') { const text = message.text.trim().slice(0, 240); if (text) { void persistChat(room.code, client.playerId, text); publish(room, { type: 'CHAT', playerId: client.playerId, name: room.players.find((p) => p.id === client.playerId)?.name, text, at: Date.now() }); } }
  if (message.type === 'SEND_STICKER') {
    const target = room.players.find((player) => player.id === message.targetPlayerId);
    const sticker = String(message.sticker);
    if (!target || target.id === client.playerId || !stickers.has(sticker)) return fail(client.socket, 'Choose a valid player and sticker.');
    // Everyone receives the event and can place it over the selected target.
    publish(room, { type: 'STICKER', targetPlayerId: target.id, fromPlayerId: client.playerId, fromName: room.players.find((player) => player.id === client.playerId)?.name || 'Guest', sticker, at: Date.now() });
  }
}
const http = createServer((_request, response) => { response.writeHead(200, { 'content-type': 'application/json' }); response.end(JSON.stringify({ service: 'rally-ludo-realtime', rooms: rooms.size })); });
const wss = new WebSocketServer({ server: http });
const alive = new WeakSet<WebSocket>();
setInterval(() => {
  for (const socket of wss.clients) {
    if (!alive.has(socket)) { socket.terminate(); continue; }
    alive.delete(socket);
    socket.ping();
  }
}, 15000).unref();
wss.on('connection', (socket, request) => {
  alive.add(socket);
  socket.on('pong', () => alive.add(socket));
  const token = new URL(request.url || '/', 'http://localhost').searchParams.get('session');
  const existing = token ? sessions.get(token) : undefined;
  const client: Client = existing ?? { socket, playerId: id('guest'), sessionToken: randomBytes(24).toString('hex') };
  if (client.disconnectTimer) clearTimeout(client.disconnectTimer);
  const previousSocket = client.socket;
  client.socket = socket;
  sessions.set(client.sessionToken, client);
  if (previousSocket !== socket) previousSocket.close();
  const room = client.roomCode ? rooms.get(client.roomCode) : undefined;
  if (room) room.clients.set(client.playerId, client);
  send(socket, { type: 'CONNECTED', playerId: client.playerId, sessionToken: client.sessionToken, resumed: Boolean(room), recoveryAvailable: true });
  syncState(client);
  socket.on('message', raw => { if (client.socket !== socket) return; try { handle(client, JSON.parse(raw.toString()) as ClientMessage); } catch { fail(socket, 'Invalid message.'); } });
  socket.on('close', () => {
    const room = client.roomCode ? rooms.get(client.roomCode) : undefined;
    if (client.socket !== socket) return;
    room?.clients.delete(client.playerId);
    client.disconnectTimer = setTimeout(() => {
      sessions.delete(client.sessionToken);
      if (!room) return;
      const turnDeparted = room.state.currentPlayer === client.playerId;
      room.state = removePlayer(room.state, client.playerId);
      room.players = room.state.players;
      if (!room.players.length) { rooms.delete(room.code); return; }
      if (room.state.phase === 'finished' || turnDeparted) {
        room.busyUntil = 0;
        resetClock(room);
      }
      void persistRoom(room.code, room.players, room.state);
      state(room);
    }, reconnectGraceMs);
    client.disconnectTimer.unref();
  });
});
const port = Number(process.env.PORT || 8787); http.listen(port, () => console.log(`Rally Ludo realtime server listening on http://localhost:${port} (${persistenceEnabled() ? 'Supabase persistence on' : 'local persistence only'})`));
