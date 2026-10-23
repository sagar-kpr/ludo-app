import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { createServer } from 'node:net';
import { expect, it } from 'vitest';
import { WebSocket } from 'ws';

it('keeps an active Bot room alive when another connection sends an invalid frame', async () => {
  const probe = createServer();
  await new Promise<void>(resolve => probe.listen(0, '127.0.0.1', resolve));
  const port = (probe.address() as { port: number }).port;
  await new Promise<void>(resolve => probe.close(() => resolve()));
  const server = spawn(process.execPath, ['--import','tsx','apps/game-server/src/index.ts'], {
    env: { ...process.env, PORT: String(port), SUPABASE_SERVICE_ROLE_KEY: '' }, stdio: ['ignore','pipe','pipe'],
  });
  const sockets: WebSocket[] = [];
  const sleep = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));
  try {
    await new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Server startup timed out')), 10000);
      server.stdout!.on('data', data => { if (String(data).includes('listening')) { clearTimeout(timer); resolve(); } });
      server.once('error', error => { clearTimeout(timer); reject(error); });
    });
    const connect = async () => {
      const socket = new WebSocket(`ws://127.0.0.1:${port}`);
      sockets.push(socket);
      const events: any[] = [];
      socket.on('message', raw => events.push(JSON.parse(String(raw))));
      socket.on('error', () => {});
      await once(socket, 'open');
      return { socket, events };
    };
    const wait = async (events: any[], type: string, from = 0) => {
      for (let attempt = 0; attempt < 200; attempt++) {
        const event = events.slice(from).find(event => event.type === type);
        if (event) return event;
        await sleep(10);
      }
      throw new Error(`Missing ${type}`);
    };
    const player = await connect();
    player.socket.send(JSON.stringify({ type:'CREATE_COMPUTER_GAME',name:'Still playing' }));
    const before = await wait(player.events,'STATE');
    const invalid = await connect();
    // Invalid RSV1 bit, injected only into this local test's TCP connection.
    (invalid.socket as unknown as { _socket: { write(data: Buffer): void } })._socket.write(Buffer.from([0xc1,0x80,0,0,0,0]));
    await once(invalid.socket,'close');
    await sleep(100);
    expect(server.exitCode,'A bad connection must not crash every active room').toBeNull();
    const from = player.events.length;
    player.socket.send(JSON.stringify({ type:'PING' }));
    expect((await wait(player.events,'PONG',from)).serverTime).toBeGreaterThan(0);
    player.socket.send(JSON.stringify({ type:'SYNC_STATE' }));
    const after = await wait(player.events,'STATE',from);
    expect(after.roomCode).toBe(before.roomCode);
    expect(after.state).toEqual(before.state);
  } finally {
    sockets.forEach(socket => socket.terminate());
    server.kill();
  }
},15000);
