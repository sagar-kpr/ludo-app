import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { createServer } from 'node:net';
import { expect, it } from 'vitest';
import { WebSocket } from 'ws';
import { DICE_ROLL_MS } from '../../../packages/shared/src/dice';
import { HOME } from '../../../packages/game-engine/src/index';
import { chooseComputerToken } from './computer-player';

type Peer = { socket: WebSocket; events: any[] };
const sleep = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));
const send = (peer: Peer, message: unknown) => peer.socket.send(JSON.stringify(message));
async function wait(peer: Peer, predicate: (event: any) => boolean, from = 0, timeoutMs = 15000): Promise<any> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const event = peer.events.slice(from).find(predicate);
    if (event) return event;
    await sleep(10);
  }
  throw new Error('Missing computer-game event: ' + String(predicate));
}

async function withServer(preload: string, run: (connect: (session?: string) => Promise<Peer>, port: number) => Promise<void>, turnMs = '30000') {
  const probe = createServer();
  await new Promise<void>(resolve => probe.listen(0, '127.0.0.1', resolve));
  const port = (probe.address() as { port: number }).port;
  await new Promise<void>(resolve => probe.close(() => resolve()));
  const server = spawn(process.execPath, ['--import', 'tsx', '--import', 'data:text/javascript;base64,' + Buffer.from(preload).toString('base64'), 'apps/game-server/src/index.ts'], {
    env: { ...process.env, PORT: String(port), TURN_TIMEOUT_MS: turnMs, RECONNECT_GRACE_MS: '700', SUPABASE_SERVICE_ROLE_KEY: '' }, stdio: ['ignore', 'pipe', 'pipe'],
  });
  const sockets: WebSocket[] = [];
  try {
    await new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Server startup timed out')), 10000);
      server.stdout!.on('data', data => { if (String(data).includes('listening')) { clearTimeout(timer); resolve(); } });
      server.once('error', error => { clearTimeout(timer); reject(error); });
      server.once('exit', code => { clearTimeout(timer); reject(new Error(`Server exited: ${code}`)); });
    });
    const connect = async (session?: string) => {
      const peer: Peer = { socket: new WebSocket(`ws://127.0.0.1:${port}/${session ? '?session=' + session : ''}`), events: [] };
      sockets.push(peer.socket);
      peer.socket.on('message', raw => peer.events.push({ ...JSON.parse(String(raw)), receivedAt: Date.now() }));
      await once(peer.socket, 'open');
      await wait(peer, event => event.type === 'CONNECTED');
      return peer;
    };
    await run(connect, port);
  } finally { sockets.forEach(socket => socket.close()); server.kill(); }
}

it('plays fair bot turns without spending lives, resumes, isolates friend rooms and cleans up on leave', async () => {
  // Deterministic child-only dice: human passes, computer gets 6, 6, then 5.
  await withServer("import crypto from 'node:crypto'; import {syncBuiltinESMExports} from 'node:module'; const values=[1,6,6,5]; let index=0; crypto.randomInt=(min,max)=>min===1?Math.min(values[Math.min(index++,3)],max-1):0; syncBuiltinESMExports();", async (connect, port) => {
    let human = await connect();
    const identity = human.events.find(event => event.type === 'CONNECTED');
    send(human, { type: 'CREATE_COMPUTER_GAME', name: 'Solo player', avatarId: 'funny_men_bobblehead_512x512.png' });
    const initial = await wait(human, event => event.type === 'STATE');
    const cpu = initial.state.players.find((player: any) => player.isComputer);
    expect(initial.state.phase).toBe('rolling');
    expect(initial.state.players.map((player: any) => player.color)).toEqual(['coral', 'mint']);
    expect(initial.state.players[0].avatarId).toBe('funny_men_bobblehead_512x512.png');
    expect(initial.state.tokens).toHaveLength(8);
    expect(initial.state.currentPlayer).toBe(identity.playerId);
    const visitor = await connect();
    send(visitor, { type: 'JOIN_ROOM', code: initial.roomCode, name: 'Visitor' });
    expect((await wait(visitor, event => event.type === 'ERROR')).message).toContain('Bot match');
    send(visitor, { type: 'CREATE_ROOM', name: 'Friends', avatarId: '../outside.png' });
    const friendRoom = await wait(visitor, event => event.type === 'ROOM_CREATED');
    const friend = await connect();
    send(friend, { type: 'JOIN_ROOM', code: friendRoom.roomCode, name: 'Friend', avatarId: 'funny_dancing_elephant_512x512.png' });
    const normal = await wait(friend, event => event.type === 'STATE');
    expect(normal.state.players.every((player: any) => !player.isComputer)).toBe(true);
    expect(normal.state.players[0].avatarId).toBeUndefined();
    expect(normal.state.players[1].avatarId).toBe('funny_dancing_elephant_512x512.png');
    send(human, { type: 'ROLL_DICE' });
    await wait(human, event => event.type === 'STATE' && event.state.currentPlayer === cpu.id);
    human.socket.terminate();
    human = await connect(identity.sessionToken);
    const recovered = await wait(human, event => event.type === 'STATE' && event.recovered);
    expect(recovered.state.players.find((player: any) => player.id === cpu.id).isComputer).toBe(true);
    expect(recovered.state.players.find((player: any) => player.id === identity.playerId).avatarId).toBe('funny_men_bobblehead_512x512.png');
    const illegalStart = human.events.length;
    send(human, { type: 'MOVE_TOKEN', tokenId: cpu.id + '-0' });
    await wait(human, event => event.type === 'ERROR', illegalStart);
    const returned = await wait(human, event => event.type === 'STATE' && event.state.currentPlayer === identity.playerId && event.state.version >= initial.state.version + 7);
    const rolls = human.events.filter(event => event.type === 'DICE_ROLLED' && event.playerId === cpu.id);
    expect(rolls.map(event => event.value)).toEqual([6, 6, 5]);
    expect(rolls.every(event => !event.timedOut)).toBe(true);
    expect(returned.state.timeoutLives).toEqual({ [identity.playerId]: 5, [cpu.id]: 5 });
    const moves = human.events.filter(event => event.type === 'TOKEN_MOVED');
    expect(moves).toHaveLength(3);
    expect(moves.every(event => event.tokenId.startsWith(cpu.id + '-') && !event.timedOut)).toBe(true);
    expect(moves[0].receivedAt - rolls[0].receivedAt).toBeGreaterThanOrEqual(DICE_ROLL_MS);
    expect(returned.state.tokens.some((token: any) => token.color === 'mint' && token.position > 0)).toBe(true);
    send(human, { type: 'LEAVE_GAME' });
    await wait(human, event => event.type === 'LEFT_ROOM');
    const afterLeave = visitor.events.length;
    send(visitor, { type: 'SYNC_STATE' });
    expect((await wait(visitor, event => event.type === 'STATE', afterLeave)).roomCode).toBe(friendRoom.roomCode);
    expect(((await (await fetch(`http://127.0.0.1:${port}`)).json()) as { rooms: number }).rooms).toBe(1);
    const newStart = human.events.length;
    send(human, { type: 'CREATE_ROOM', name: 'Back to friends' });
    const fresh = await wait(human, event => event.type === 'STATE', newStart);
    expect(fresh.state.phase).toBe('lobby');
    expect(fresh.state.players).toHaveLength(1);
  });
}, 25000);

it('finishes and restarts a complete computer match through real server messages', async () => {
  // Accelerate only this child process's presentation clock. Production has no
  // fixture endpoint, rigged dice setting, or shortened animation constants.
  const speed = 100;
  const preload = `import crypto from 'node:crypto'; import {syncBuiltinESMExports} from 'node:module'; const realNow=Date.now.bind(Date); const origin=realNow(); Date.now=()=>origin+(realNow()-origin)*${speed}; let seed=47; crypto.randomInt=(min,max)=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return min+seed%(max-min)}; syncBuiltinESMExports();`;
  await withServer(preload, async connect => {
    const human = await connect();
    const id = human.events.find(event => event.type === 'CONNECTED').playerId;
    let action: ReturnType<typeof setTimeout> | undefined;
    const act = (raw: unknown) => {
      const event = JSON.parse(String(raw));
      if (event.type !== 'STATE') return;
      clearTimeout(action);
      if (event.state.currentPlayer !== id || event.state.phase === 'finished') return;
      const waitMs = Math.max(0, (event.turnDeadline - event.turnDurationMs - event.serverTime) / speed) + 12;
      action = setTimeout(() => {
        if (event.state.phase === 'rolling') send(human, { type: 'ROLL_DICE' });
        else {
          const token = chooseComputerToken(event.state);
          if (token) send(human, { type: 'MOVE_TOKEN', tokenId: token.id });
        }
      }, waitMs);
    };
    human.socket.on('message', act);
    try {
      send(human, { type: 'CREATE_COMPUTER_GAME', name: 'Human' });
      const complete = await wait(human, event => event.type === 'STATE' && event.state.phase === 'finished', 0, 50000);
      human.socket.off('message', act);
      clearTimeout(action);
      expect(human.events.filter(event => event.type === 'ERROR')).toEqual([]);
      expect(complete.state.finishOrder).toHaveLength(2);
      const winner = complete.state.players.find((player: any) => player.id === complete.state.winner);
      expect(complete.state.tokens.filter((token: any) => token.color === winner.color).every((token: any) => token.position === HOME)).toBe(true);
      expect(Object.values(complete.state.timeoutLives)).toEqual([5, 5]);
      const lastMove = human.events.filter(event => event.type === 'TOKEN_MOVED').at(-1);
      await sleep(((lastMove?.durationMs ?? 0) + (lastMove?.delayMs ?? 0) + (lastMove?.captureDurationMs ?? 0)) / speed + 30);
      const restartFrom = human.events.length;
      send(human, { type: 'RESTART_GAME' });
      const restarted = await wait(human, event => event.type === 'STATE', restartFrom);
      expect(restarted.state.phase).toBe('rolling');
      expect(restarted.state.currentPlayer).toBe(id);
      expect(restarted.state.tokens.every((token: any) => token.position === 0)).toBe(true);
      expect(restarted.state.players[1].isComputer).toBe(true);
      const version = restarted.state.version;
      await sleep(200);
      send(human, { type: 'SYNC_STATE' });
      const stable = await wait(human, event => event.type === 'STATE' && event.recovered, restartFrom);
      expect(stable.state.version).toBe(version);
      send(human, { type: 'LEAVE_GAME' });
      await wait(human, event => event.type === 'LEFT_ROOM', restartFrom);
    } finally { human.socket.off('message', act); clearTimeout(action); }
  }, '120000');
}, 60000);
