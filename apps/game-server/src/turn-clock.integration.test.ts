import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { once } from 'node:events';
import { WebSocket } from 'ws';
import { expect, it } from 'vitest';

function receive(socket: WebSocket, predicate: (event: any) => boolean): Promise<any> {
  return new Promise((resolve,reject) => {
    const timer = setTimeout(() => { socket.off('message',listener); reject(new Error('Timed out waiting for server event')); },4000);
    const listener = (raw: unknown) => {
      const event = JSON.parse(String(raw));
      if (predicate(event)) { clearTimeout(timer); socket.off('message',listener); resolve(event); }
    };
    socket.on('message',listener);
  });
}
it('broadcasts a real deadline and passes an expired turn identically to both clients', async () => {
  const probe = createServer();
  await new Promise<void>(resolve => probe.listen(0,'127.0.0.1',resolve));
  const port = (probe.address() as {port:number}).port;
  await new Promise<void>(resolve => probe.close(() => resolve()));
  const server = spawn(process.execPath,['--import','tsx','apps/game-server/src/index.ts'],{env:{...process.env,PORT:String(port),TURN_TIMEOUT_MS:'1000',SUPABASE_SERVICE_ROLE_KEY:''},stdio:['ignore','pipe','pipe']});
  const sockets: WebSocket[] = [];
  try {
    await new Promise<void>((resolve,reject) => {
      const timer = setTimeout(() => reject(new Error('Server startup timed out')),5000);
      server.stdout!.on('data',data => { if (String(data).includes('listening')) { clearTimeout(timer); resolve(); } });
      server.once('error',error => { clearTimeout(timer); reject(error); });
    });
    for (let index=0;index<2;index++) {
      const socket = new WebSocket(`ws://127.0.0.1:${port}`);
      sockets.push(socket); await once(socket,'open');
    }
    const [host,friend] = sockets;
    const created = receive(host,e => e.type === 'ROOM_CREATED');
    host.send(JSON.stringify({type:'CREATE_ROOM',name:'Host'}));
    const {roomCode} = await created;
    const joined = receive(friend,e => e.type === 'STATE' && e.state.players.length === 2);
    friend.send(JSON.stringify({type:'JOIN_ROOM',code:roomCode,name:'Friend'})); await joined;
    const denied = receive(friend,e => e.type === 'ERROR');
    friend.send(JSON.stringify({type:'RESTART_GAME'}));
    expect((await denied).message).toContain('Only the host');
    const premature = receive(host,e => e.type === 'ERROR');
    host.send(JSON.stringify({type:'RESTART_GAME'}));
    expect((await premature).message).toContain('Finish the match');
    const started = receive(host,e => e.type === 'STATE' && e.state.phase === 'rolling');
    host.send(JSON.stringify({type:'START_GAME'}));
    const before = await started;
    expect(before.turnDeadline-before.serverTime).toBeGreaterThan(900);
    expect(before.turnDurationMs).toBe(1000);
    const expired = (e: any) => e.type === 'STATE' && e.state.version > before.state.version;
    const [a,b] = await Promise.all([receive(host,expired),receive(friend,expired)]);
    expect(a.state).toEqual(b.state);
    expect(a.turnDeadline).toBe(b.turnDeadline);
    expect(a.state.currentPlayer).toBe(before.state.players[1].id);
    expect(a.state.tokens).toEqual(before.state.tokens);
    const rejected = receive(host,e => e.type === 'ERROR');
    host.send(JSON.stringify({type:'ROLL_DICE'}));
    expect((await rejected).message).toContain('not your turn');
  } finally { sockets.forEach(socket => socket.close()); server.kill(); }
},10000);
