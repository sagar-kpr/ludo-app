import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { afterAll, beforeAll, expect, it } from 'vitest';
import { WebSocket } from 'ws';
import { DICE_ROLL_MS } from '../../../packages/shared/src/dice';

const port = 19000 + Math.floor(Math.random() * 1000);
let server: ReturnType<typeof spawn>;
const sockets: WebSocket[] = [];
beforeAll(async () => {
  server = spawn(process.execPath, ['--import', 'tsx', 'apps/game-server/src/index.ts'], {
    env: { ...process.env, PORT: String(port), SUPABASE_SERVICE_ROLE_KEY: '', RECONNECT_GRACE_MS: '1000' },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  await new Promise<void>((resolve, reject) => {
    server.stdout!.on('data', (data) => { if (String(data).includes('listening')) resolve(); });
    server.on('error', reject);
    server.on('exit', (code) => { if (code) reject(new Error(`Server exited: ${code}`)); });
  });
});
afterAll(() => { sockets.forEach((s) => s.close()); server?.kill(); });
it('broadcasts a win and removes tokens when the opponent disconnects', async () => {
  const host = await client();
  const guest = await client();
  const created = receive(host, 'ROOM_CREATED');
  host.send(JSON.stringify({ type: 'CREATE_ROOM', name: 'Host' }));
  const { roomCode } = await created;
  const joined = receive(guest, 'STATE');
  guest.send(JSON.stringify({ type: 'JOIN_ROOM', code: roomCode, name: 'Guest' }));
  await joined;
  const started = receive(host, 'STATE');
  host.send(JSON.stringify({ type: 'START_GAME' }));
  await started;
  const departed = receive(host, 'STATE');
  guest.close();
  const snapshot = await departed;
  expect(snapshot.state.phase).toBe('finished');
  expect(snapshot.state.winner).toBe(snapshot.state.players[0].id);
  expect(snapshot.state.players).toHaveLength(1);
  expect(snapshot.state.tokens).toHaveLength(4);
  expect(snapshot.turnDeadline).toBe(0);
});
async function client() {
  const socket = new WebSocket(`ws://localhost:${port}`);
  sockets.push(socket);
  await once(socket, 'open');
  return socket;
}
function receive(socket: WebSocket, type: string) {
  return new Promise<any>((resolve, reject) => {
    const timer = setTimeout(() => { socket.off('message', listener); reject(new Error(`Missing ${type}`)); }, 3000);
    const listener = (data: unknown) => {
      const event = JSON.parse(String(data));
      if (event.type === type) { clearTimeout(timer); socket.off('message', listener); resolve(event); }
    };
    socket.on('message', listener);
  });
}
it('resumes the same player and match, then accepts chat and heartbeat without restarting', async () => {
  const host = await client();
  const guest = new WebSocket(`ws://localhost:${port}`);
  sockets.push(guest);
  const connected = receive(guest, 'CONNECTED');
  await once(guest, 'open');
  const identity = await connected;
  const created = receive(host, 'ROOM_CREATED');
  host.send(JSON.stringify({ type: 'CREATE_ROOM', name: 'Host' }));
  const { roomCode } = await created;
  const joined = receive(guest, 'STATE');
  guest.send(JSON.stringify({ type: 'JOIN_ROOM', code: roomCode, name: 'Guest' }));
  await joined;
  const starting = receive(guest, 'STATE');
  host.send(JSON.stringify({ type: 'START_GAME' }));
  const before = await starting;
  guest.terminate();
  const resumed = new WebSocket(`ws://localhost:${port}/?session=${identity.sessionToken}`);
  sockets.push(resumed);
  const reconnected = receive(resumed, 'CONNECTED');
  const snapshot = receive(resumed, 'STATE');
  await once(resumed, 'open');
  expect((await reconnected).playerId).toBe(identity.playerId);
  const after = await snapshot;
  expect(after.recovered).toBe(true);
  expect(after.state).toEqual(before.state);
  expect(after.turnDeadline).toBe(before.turnDeadline);
  const pong = receive(resumed, 'PONG');
  resumed.send(JSON.stringify({ type: 'PING' }));
  expect((await pong).serverTime).toBeGreaterThan(0);
  const chat = receive(host, 'CHAT');
  resumed.send(JSON.stringify({ type: 'CHAT', text: 'Back online' }));
  expect((await chat).playerId).toBe(identity.playerId);
  await new Promise(resolve => setTimeout(resolve, 1100));
  const synced = receive(resumed, 'STATE');
  resumed.send(JSON.stringify({ type: 'SYNC_STATE' }));
  expect((await synced).state.players).toHaveLength(2);
});
it('rejects unknown codes and joins an existing room without creating another', async () => {
  const host = await client();
  const guest = await client();
  const created = receive(host, 'ROOM_CREATED');
  host.send(JSON.stringify({ type: 'CREATE_ROOM', name: 'Host' }));
  const { roomCode } = await created;
  const rejected = receive(guest, 'ERROR');
  guest.send(JSON.stringify({ type: 'JOIN_ROOM', code: 'INVALID', name: 'Friend' }));
  expect((await rejected).message).toContain('Room not found');
  const joined = receive(guest, 'ROOM_JOINED');
  const hostState = receive(host, 'STATE');
  const guestState = receive(guest, 'STATE');
  guest.send(JSON.stringify({ type: 'JOIN_ROOM', code: roomCode.toLowerCase(), name: 'Friend' }));
  expect((await joined).roomCode).toBe(roomCode);
  const hostSnapshot = await hostState;
  const guestSnapshot = await guestState;
  expect(hostSnapshot.players.map((p: { name: string }) => p.name)).toEqual(['Host', 'Friend']);
  expect(guestSnapshot.state).toEqual(hostSnapshot.state);
  const denied = receive(guest, 'ERROR');
  guest.send(JSON.stringify({ type: 'START_GAME' }));
  expect((await denied).message).toContain('Only the host');
  const hostStarted = receive(host, 'STATE');
  const guestStarted = receive(guest, 'STATE');
  host.send(JSON.stringify({ type: 'START_GAME' }));
  const started = await hostStarted;
  expect(started.turnDurationMs).toBe(60000);
  expect(started.turnDeadline - started.serverTime).toBeGreaterThanOrEqual(59000);
  let match = started.state;
  expect((await guestStarted).state).toEqual(match);
  expect(match.phase).toBe('rolling');
  expect(match.players.map((player: { color: string }) => player.color)).toEqual(['coral', 'mint']);
  const badTurn = receive(guest, 'ERROR');
  guest.send(JSON.stringify({ type: 'ROLL_DICE' }));
  expect((await badTurn).message).toContain('not your turn');
  const hostId = match.players[0].id;
  const guestId = match.players[1].id;
  // Roll until a six allows entry. Every roll must produce identical snapshots.
  for (let n = 0; n < 100 && match.phase !== 'moving'; n++) {
    const actor = match.currentPlayer === hostId ? host : guest;
    const roll = receive(actor, 'DICE_ROLLED');
    const hostNext = receive(host, 'STATE');
    const guestNext = receive(guest, 'STATE');
    actor.send(JSON.stringify({ type: 'ROLL_DICE' }));
    const result = await roll;
    if (n === 0) {
      const premature = receive(actor, 'ERROR');
      actor.send(JSON.stringify({ type: 'ROLL_DICE' }));
      expect((await premature).message).toContain('animation');
    }
    expect(result.value).toBeGreaterThanOrEqual(1);
    expect(result.value).toBeLessThanOrEqual(6);
    match = (await hostNext).state;
    expect((await guestNext).state).toEqual(match);
    expect(result.color).toBe(match.players.find((p: { id: string }) => p.id === (actor === host ? hostId : guestId)).color);
    await new Promise((resolve) => setTimeout(resolve, DICE_ROLL_MS+50));
  }
  expect(match.phase).toBe('moving');
  const actor = match.currentPlayer === hostId ? host : guest;
  const actorId = actor === host ? hostId : guestId;
  const hostMoved = receive(host, 'STATE');
  const guestMoved = receive(guest, 'STATE');
  const moveEvent = receive(actor, 'TOKEN_MOVED');
  actor.send(JSON.stringify({ type: 'MOVE_TOKEN', tokenId: actorId + '-0' }));
  const moved = (await hostMoved).state;
  expect((await guestMoved).state).toEqual(moved);
  expect(moved.tokens.find((t: { id: string }) => t.id === actorId + '-0').position).toBe(1);
  const movement = await moveEvent;
  expect(movement.from).toBe(0);
  expect(movement.to).toBe(1);
  expect(movement.automatic).toBe(false);
  const locked = receive(actor, 'ERROR');
  actor.send(JSON.stringify({ type: 'ROLL_DICE' }));
  expect((await locked).message).toContain('animation');
  const hostChat = receive(host, 'CHAT');
  const guestChat = receive(guest, 'CHAT');
  guest.send(JSON.stringify({ type: 'CHAT', text: 'Hello from my phone' }));
  expect((await hostChat).text).toBe('Hello from my phone');
  expect((await guestChat).text).toBe('Hello from my phone');

  await new Promise((resolve) => setTimeout(resolve, movement.durationMs+50));
  const rolled = receive(actor, 'DICE_ROLLED');
  const hostRolled = receive(host, 'STATE');
  const guestRolled = receive(guest, 'STATE');
  actor.send(JSON.stringify({ type: 'ROLL_DICE' }));
  const dice = await rolled;
  const waiting = (await hostRolled).state;
  expect((await guestRolled).state).toEqual(waiting);
  if (dice.value === 6) {
    expect(dice.automatic).toBe(false);
    expect(waiting.phase).toBe('moving');
    expect(waiting.tokens).toEqual(moved.tokens);
    await new Promise((resolve) => setTimeout(resolve, DICE_ROLL_MS+50));
    const hostManual = receive(host, 'STATE');
    const guestManual = receive(guest, 'STATE');
    actor.send(JSON.stringify({ type: 'MOVE_TOKEN', tokenId: actorId + '-0' }));
    const manual = (await hostManual).state;
    expect((await guestManual).state).toEqual(manual);
    expect(manual.tokens.find((t: { id: string }) => t.id === actorId + '-0').position).toBe(7);
  } else {
    expect(dice.automatic).toBe(true);
    expect(waiting.phase).toBe('rolling');
    expect(waiting.tokens.find((t: { id: string }) => t.id === actorId + '-0').position).toBe(1+dice.value);
  }

}, 60000);
