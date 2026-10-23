import 'dotenv/config';
import { randomBytes, randomInt } from 'node:crypto';
import { createServer } from 'node:http';
import { WebSocketServer, WebSocket } from 'ws';
import { MAX_TIMEOUT_LIVES, diceValuesForRoll, autoMoveToken, createGame, moveToken, rollDice, startGame, restartGame, removePlayer, type Color, type GameState, type Player } from '../../../packages/game-engine/src/index';
import { STEP_MS, captureReturnDurationMs } from '../../../packages/game-engine/src/motion';
import { STICKERS } from '../../../packages/shared/src/stickers';
import { DICE_ROLL_MS } from '../../../packages/shared/src/dice';
import { persistChat, persistRoom, persistenceEnabled } from './persistence';
import { turnTimeoutAction } from './turn-clock';
import { chooseComputerToken } from './computer-player';

type ClientMessage = { type: 'LEAVE_GAME' } | { type: 'PING' } | { type: 'SYNC_STATE' } | { type: 'CREATE_ROOM' | 'CREATE_COMPUTER_GAME'; name: string; avatarId?: string } | { type: 'JOIN_ROOM'; code: string; name: string; avatarId?: string } | { type: 'START_GAME' } | { type: 'RESTART_GAME' } | { type: 'ROLL_DICE' } | { type: 'MOVE_TOKEN'; tokenId: string } | { type: 'CHAT'; text: string } | { type: 'SEND_STICKER'; targetPlayerId: string; sticker: string };
type Client = { socket: WebSocket; playerId: string; sessionToken: string; roomCode?: string; disconnectTimer?: ReturnType<typeof setTimeout> };
type Room = { code: string; players: Player[]; state: GameState; clients: Map<string, Client>; createdAt: number; busyUntil: number; turnDeadline?: number; computerId?: string; computerActionAt?: number };
const COMPUTER_THINK_MS = 550;
const configuredTurnMs = Number(process.env.TURN_TIMEOUT_MS || 30000);
const turnDurationMs = Number.isFinite(configuredTurnMs) ? Math.max(1000, Math.min(120000, configuredTurnMs)) : 30000;
const rooms = new Map<string, Room>();
const sessions = new Map<string, Client>();
const serverInstanceId = randomBytes(8).toString('hex');
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
  room.computerActionAt = room.turnDeadline && room.state.currentPlayer === room.computerId ? Math.max(Date.now(), room.busyUntil) + COMPUTER_THINK_MS : undefined;
}
function expireRoom(room: Room) {
  if (room.state.currentPlayer === room.computerId) return false;
  if (!room.turnDeadline || Date.now() < room.turnDeadline || Date.now() < room.busyUntil) return false;
  const action = turnTimeoutAction(room.state, () => randomInt(0, 0x1000000) / 0x1000000);
  if (!action) return false;
  if (action.type === 'pass') {
    // An impossible move is not inactivity; there was no choice to make.
    const blockedRoll = room.state.phase === 'rolling';
    const playerId = room.state.currentPlayer;
    room.state = action.state;
    resetClock(room);
    if (blockedRoll) publish(room, { type: 'TURN_SKIPPED', playerId, reason: 'friendly_occupancy', version: room.state.version });
    state(room);
    return true;
  }
  const previous = room.state;
  const playerId = previous.currentPlayer;
  const lives = previous.timeoutLives?.[playerId] ?? MAX_TIMEOUT_LIVES;
  if (lives <= 0) {
    // Five automatic actions are allowed. Only a later missed deadline ejects
    // the player, without rolling or moving again at zero lives.
    const client = room.clients.get(playerId) ?? [...sessions.values()].find(session => session.playerId === playerId);
    removeRoomPlayer(room, playerId, client, true, 'inactivity');
    return true;
  }
  const remaining = lives - 1;
  // Apply the life change atomically with the normal roll/move version.
  room.state = { ...previous, timeoutLives: { ...previous.timeoutLives, [playerId]: remaining } };
  const applied = action.type === 'roll' ? applyRoll(room, true) : applyMove(room, action.tokenId, true, 0, true);
  if (!applied) { room.state = previous; return false; }
  return true;
}
function playComputerTurn(room: Room) {
  if (!room.computerActionAt || Date.now() < room.computerActionAt || Date.now() < room.busyUntil || room.state.currentPlayer !== room.computerId) return;
  room.computerActionAt = undefined;
  if (room.state.phase === 'rolling') { applyRoll(room); return; }
  if (room.state.phase !== 'moving') return;
  const token = chooseComputerToken(room.state);
  if (token) { applyMove(room, token.id, true, 0); return; }
  const action = turnTimeoutAction(room.state);
  if (action?.type === 'pass') { room.state = action.state; resetClock(room); state(room); }
}
setInterval(() => {
  for (const room of rooms.values()) if (room.clients.size) {
    if (room.computerId && room.state.currentPlayer === room.computerId) playComputerTurn(room);
    else expireRoom(room);
  }
},100).unref();
const fail = (socket: WebSocket, message: string) => send(socket, { type: 'ERROR', message });
const stickers = new Set<string>(STICKERS);

function avatarMetadata(value: unknown): Pick<Player, 'avatarId'> {
  return typeof value === 'string' && /^[a-zA-Z0-9_-]{1,100}\.(png|jpg|jpeg|webp)$/i.test(value) ? { avatarId: value } : {};
}
function createRoom(client: Client, name: string, computer = false, avatarId?: string) {
  if (client.roomCode) return fail(client.socket, 'You already belong to a room.');
  const player: Player = { id: client.playerId, name: name.trim().slice(0, 18) || 'Guest', color: colors[0], ready: true, ...avatarMetadata(avatarId) };
  const room: Room = { code: code(), players: [player], state: createGame([player]), clients: new Map([[client.playerId, client]]), createdAt: Date.now(), busyUntil: 0 };
  if (computer) {
    const opponent: Player = { id: id('computer'), name: 'A.I', color: colors[1], ready: true, isComputer: true };
    room.computerId = opponent.id;
    room.players.push(opponent);
    room.state = startGame(createGame(room.players));
    resetClock(room);
  }
  client.roomCode = room.code; rooms.set(room.code, room); void persistRoom(room.code, room.players, room.state); send(client.socket, { type: 'ROOM_CREATED', roomCode: room.code, playerId: client.playerId }); state(room);
}
function joinRoom(client: Client, value: string, name: string, avatarId?: string) {
  if (client.roomCode) return fail(client.socket, 'You already belong to a room.');
  const room = rooms.get(value.toUpperCase());
  if (!room) return fail(client.socket, 'Room not found. Check the invite code.');
  if (room.computerId) return fail(client.socket, 'This is an A.I match. Create or join a friend room instead.');
  if (room.players.length >= 4) return fail(client.socket, 'This room is full.');
  if (room.state.phase !== 'lobby') return fail(client.socket, 'This match has already started.');
  const player: Player = { id: client.playerId, name: name.trim().slice(0, 18) || 'Guest', color: colors.find(color => !room.players.some(player => player.color === color))!, ready: true, ...avatarMetadata(avatarId) };
  room.players.push(player); room.state = { ...createGame(room.players), version: room.state.version + 1 }; room.clients.set(client.playerId, client); client.roomCode = room.code; void persistRoom(room.code, room.players, room.state); send(client.socket, { type: 'ROOM_JOINED', roomCode: room.code, playerId: client.playerId }); state(room);
}
function applyMove(room: Room, tokenId: string, automatic = false, presentationMs = DICE_ROLL_MS, timedOut = false) {
  const previous = room.state;
  const next = moveToken(previous, tokenId);
  if (next === previous) return false;
  const from = previous.tokens.find((t) => t.id === tokenId)!.position;
  const to = next.tokens.find((t) => t.id === tokenId)!.position;
  const captured = next.tokens.filter((t) => t.position === 0 && previous.tokens.find((p) => p.id === t.id)!.position > 0).map((t) => t.id);
  room.state = next;
  const durationMs = (from === 0 ? 1 : to-from)*STEP_MS;
  const delayMs = automatic ? presentationMs : 0;
  const captureDurationMs = captured.reduce((total, id) => total+captureReturnDurationMs(previous.tokens.find(token => token.id === id)!.position), 0);
  room.busyUntil = Date.now()+delayMs+durationMs+captureDurationMs;
  resetClock(room);
  publish(room, { type: 'TOKEN_MOVED', tokenId, from, to, captured, automatic, timedOut, durationMs, captureDurationMs, delayMs, version: next.version });
  state(room);
  return true;
}
function applyRoll(room: Room, timedOut = false) {
  const playerId = room.state.currentPlayer;
  const color = room.players.find(player => player.id === playerId)?.color;
  const values = diceValuesForRoll(room.state);
  const bucket = values.length ? randomInt(1, values.length+1)-1 : 0;
  const value = values[bucket];
  const next = rollDice(room.state, () => (bucket+0.5)/Math.max(1, values.length));
  if (next === room.state) return false;
  room.state = next;
  if (value === undefined) {
    room.busyUntil = Date.now();
    resetClock(room);
    publish(room, { type: 'TURN_SKIPPED', playerId, reason: 'friendly_occupancy', version: next.version });
    state(room);
    return true;
  }
  const presentationMs = DICE_ROLL_MS;
  room.busyUntil = Date.now()+presentationMs;
  resetClock(room);
  const automatic = autoMoveToken(next);
  publish(room, { type: 'DICE_ROLLED', value, playerId, color, timedOut, skipped: next.phase === 'rolling', automatic: Boolean(automatic), version: next.version });
  if (automatic) return applyMove(room, automatic.id, true, presentationMs);
  state(room);
  return true;
}
function leaveRoom(client: Client, acknowledge = false) {
  const room = client.roomCode ? rooms.get(client.roomCode) : undefined;
  if (room) removeRoomPlayer(room, client.playerId, client, acknowledge);
}
function removeRoomPlayer(room: Room, playerId: string, client?: Client, acknowledge = false, reason = 'voluntary') {
  const turnDeparted = room.state.currentPlayer === playerId;
  room.state = removePlayer(room.state, playerId);
  room.players = room.state.players;
  if (room.state.phase !== 'lobby') {
    room.busyUntil = Math.max(Date.now(), room.busyUntil) + 1350;
    if (room.state.phase === 'finished' || turnDeparted) resetClock(room);
    else if (room.turnDeadline) room.turnDeadline += 1350;
  }
  // Include the leaving client in the final snapshot so it sees its pawn exit.
  void persistRoom(room.code, room.players, room.state);
  state(room);
  room.clients.delete(playerId);
  if (client) {
    client.roomCode = undefined;
    if (acknowledge) send(client.socket, { type: 'LEFT_ROOM', roomCode: room.code, reason });
  }
  if (!room.players.length || (room.computerId && !room.players.some(player => player.id !== room.computerId))) rooms.delete(room.code);
}
function handle(client: Client, message: ClientMessage) {
  if (message.type === 'PING') { send(client.socket, { type: 'PONG', serverTime: Date.now() }); return; }
  if (message.type === 'SYNC_STATE') { syncState(client); return; }
  if (message.type === 'CREATE_ROOM') return createRoom(client, message.name, false, message.avatarId);
  if (message.type === 'CREATE_COMPUTER_GAME') return createRoom(client, message.name, true, message.avatarId);
  if (message.type === 'JOIN_ROOM') return joinRoom(client, message.code, message.name, message.avatarId);
  if (!client.roomCode) return fail(client.socket, 'Join a room first.');
  const room = rooms.get(client.roomCode); if (!room) return fail(client.socket, 'Room expired.');
  if (message.type === 'LEAVE_GAME') return leaveRoom(client, true);
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
  if ((message.type === 'ROLL_DICE' || message.type === 'MOVE_TOKEN') && expireRoom(room)) return client.roomCode ? fail(client.socket, 'Timer expired; the server acted automatically.') : undefined;
  if ((message.type === 'ROLL_DICE' || message.type === 'MOVE_TOKEN') && Date.now() < room.busyUntil) return fail(client.socket, 'Wait for the dice or token animation to finish.');
  if (message.type === 'START_GAME') {
    if (room.players[0].id !== client.playerId) return fail(client.socket, 'Only the host can start the match.');
    if (room.players.length < 2) return fail(client.socket, 'At least two players are required.');
    if (room.state.phase !== 'lobby') return fail(client.socket, 'This match has already started.');
    room.state = startGame(room.state); resetClock(room); return state(room);
  }
  if (message.type === 'ROLL_DICE') {
    if (room.state.currentPlayer !== client.playerId) return fail(client.socket, 'It is not your turn.');
    if (!applyRoll(room)) fail(client.socket, 'Dice cannot be rolled right now.');
    return;
  }
  if (message.type === 'MOVE_TOKEN') {
    if (room.state.currentPlayer !== client.playerId) return fail(client.socket, 'It is not your turn.');
    if (!applyMove(room, message.tokenId)) fail(client.socket, 'That token cannot move.');
    return;
  }
  if (room.computerId && (message.type === 'CHAT' || message.type === 'SEND_STICKER')) return fail(client.socket, 'Chat and reactions are available in friend rooms.');
  if (message.type === 'CHAT') { const text = message.text.trim().slice(0, 240); if (text) { void persistChat(room.code, client.playerId, text); publish(room, { type: 'CHAT', playerId: client.playerId, name: room.players.find((p) => p.id === client.playerId)?.name, text, at: Date.now() }); } }
  if (message.type === 'SEND_STICKER') {
    const target = room.players.find((player) => player.id === message.targetPlayerId);
    const sticker = String(message.sticker);
    if (!target || target.id === client.playerId || !stickers.has(sticker)) return fail(client.socket, 'Choose a valid player and sticker.');
    // Everyone receives the event and can place it over the selected target.
    publish(room, { type: 'STICKER', targetPlayerId: target.id, fromPlayerId: client.playerId, fromName: room.players.find((player) => player.id === client.playerId)?.name || 'Guest', sticker, at: Date.now() });
  }
}
const http = createServer((_request, response) => { response.writeHead(200, { 'content-type': 'application/json' }); response.end(JSON.stringify({ service: 'rally-ludo-realtime', rooms: rooms.size, serverInstanceId })); });
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
  // Protocol/socket errors belong to this connection, not the server process.
  socket.on('error', error => {
    console.warn('[realtime] connection error:', error.message);
    socket.terminate();
  });
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
  send(socket, { type: 'CONNECTED', playerId: client.playerId, sessionToken: client.sessionToken, resumed: Boolean(room), recoveryAvailable: true, serverInstanceId });
  syncState(client);
  socket.on('message', raw => { if (client.socket !== socket) return; try { handle(client, JSON.parse(raw.toString()) as ClientMessage); } catch { fail(socket, 'Invalid message.'); } });
  socket.on('close', () => {
    const room = client.roomCode ? rooms.get(client.roomCode) : undefined;
    if (client.socket !== socket) return;
    room?.clients.delete(client.playerId);
    client.disconnectTimer = setTimeout(() => {
      sessions.delete(client.sessionToken);
      if (!room) return;
      leaveRoom(client);
    }, reconnectGraceMs);
    client.disconnectTimer.unref();
  });
});
const port = Number(process.env.PORT || 8787); http.listen(port, () => console.log(`Rally Ludo realtime server listening on http://localhost:${port} (${persistenceEnabled() ? 'Supabase metadata on' : 'no database'}; matches in memory; instance ${serverInstanceId})`));
