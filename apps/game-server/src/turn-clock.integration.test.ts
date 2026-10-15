import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { once } from 'node:events';
import { WebSocket } from 'ws';
import { expect, it } from 'vitest';
import { DICE_ROLL_MS } from '../../../packages/shared/src/dice';

function receive(socket: WebSocket, predicate: (event: any) => boolean, timeoutMs = 5000): Promise<any> {
  return new Promise((resolve,reject) => {
    const timer = setTimeout(() => { socket.off('message',listener); reject(new Error('Timed out waiting for server event')); },timeoutMs);
    const listener = (raw: unknown) => {
      const event = JSON.parse(String(raw));
      if (predicate(event)) { clearTimeout(timer); socket.off('message',listener); resolve(event); }
    };
    socket.on('message',listener);
  });
}
async function withMatch(value: number | number[], run: (host: WebSocket, friend: WebSocket, before: any) => Promise<void>) {
  const probe = createServer();
  await new Promise<void>(resolve => probe.listen(0,'127.0.0.1',resolve));
  const port = (probe.address() as {port:number}).port;
  await new Promise<void>(resolve => probe.close(() => resolve()));
  // A child-only Node preload makes real WS timeout tests deterministic.
  // Production has no fixture endpoint or configurable dice values.
  const preload = 'data:text/javascript;base64,' + Buffer.from(`import crypto from 'node:crypto'; import {syncBuiltinESMExports} from 'node:module'; const faces=${JSON.stringify(Array.isArray(value) ? value : [value])}; let roll=0; crypto.randomInt=(min,max)=>min===1?Math.min(faces[Math.min(roll++,faces.length-1)],max-1):0; syncBuiltinESMExports();`).toString('base64');
  const server = spawn(process.execPath,['--import','tsx','--import',preload,'apps/game-server/src/index.ts'],{env:{...process.env,PORT:String(port),TURN_TIMEOUT_MS:'1000',SUPABASE_SERVICE_ROLE_KEY:''},stdio:['ignore','pipe','pipe']});
  const sockets: WebSocket[] = [];
  try {
    await new Promise<void>((resolve,reject) => {
      const timer = setTimeout(() => reject(new Error('Server startup timed out')),5000);
      server.stdout!.on('data',data => { if (String(data).includes('listening')) { clearTimeout(timer); resolve(); } });
      server.once('error',error => { clearTimeout(timer); reject(error); });
      server.once('exit',code => {clearTimeout(timer);reject(new Error(`Server exited ${code}`));});
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
    const started = receive(host,e => e.type === 'STATE' && e.state.phase === 'rolling');
    host.send(JSON.stringify({type:'START_GAME'}));
    const before = await started;
    expect(before.turnDeadline-before.serverTime).toBeGreaterThan(900);
    expect(before.turnDurationMs).toBe(1000);
    await run(host,friend,before);
  } finally { sockets.forEach(socket => socket.close()); server.kill(); }
}
it('auto-rolls, gives a fresh move deadline, then broadcasts one valid timeout move to both clients', async () => {
  await withMatch(6, async (host,friend,before) => {
    const rolls = [host,friend].map(socket=>receive(socket,e=>e.type==='DICE_ROLLED'));
    const snapshots = [host,friend].map(socket=>receive(socket,e=>e.type==='STATE' && e.state.version>before.state.version));
    const [rollA,rollB] = await Promise.all(rolls);
    expect(rollA).toEqual(rollB);
    expect(rollA.timedOut).toBe(true);
    expect(rollA.value).toBe(6);
    expect(rollA.automatic).toBe(false); // Four legal pawns: allow selection time.
    const [a,b] = await Promise.all(snapshots);
    expect(a.state).toEqual(b.state);
    expect(a.turnDeadline).toBe(b.turnDeadline);
    expect(a.state.currentPlayer).toBe(before.state.currentPlayer);
    expect(a.state.phase).toBe('moving');
    expect(a.state.timeoutLives[before.state.currentPlayer]).toBe(4);
    expect(a.turnDeadline-a.serverTime).toBeGreaterThanOrEqual(DICE_ROLL_MS+950);
    expect(a.turnDeadline).toBeGreaterThan(before.turnDeadline+DICE_ROLL_MS+900);
    const premature = receive(host,e=>e.type==='ERROR');
    host.send(JSON.stringify({type:'MOVE_TOKEN',tokenId:a.state.tokens[0].id}));
    expect((await premature).message).toContain('animation');
    const moves = [host,friend].map(socket=>receive(socket,e=>e.type==='TOKEN_MOVED'));
    const after = [host,friend].map(socket=>receive(socket,e=>e.type==='STATE' && e.state.version>a.state.version));
    const [moveA,moveB] = await Promise.all(moves);
    expect(moveA).toEqual(moveB);
    expect(moveA.timedOut).toBe(true);
    expect(moveA.automatic).toBe(true);
    expect(moveA.from).toBe(0);
    expect(moveA.to).toBe(1);
    expect(moveA.delayMs).toBe(0); // No second dice delay on move timeout.
    const [c,d] = await Promise.all(after);
    expect(c.state).toEqual(d.state);
    expect(c.turnDeadline).toBe(d.turnDeadline);
    expect(c.state.currentPlayer).toBe(before.state.currentPlayer); // Six bonus.
    expect(c.state.tokens.filter((token:any)=>token.position===1)).toHaveLength(1);
    expect(c.state.version).toBe(before.state.version+2);
    expect(c.state.timeoutLives[before.state.currentPlayer]).toBe(3);
    const stale = receive(host,e=>e.type==='ERROR');
    host.send(JSON.stringify({type:'MOVE_TOKEN',tokenId:moveA.tokenId}));
    expect((await stale).message).toContain('animation');
    const recovered = receive(host,e=>e.type==='STATE' && e.recovered);
    host.send(JSON.stringify({type:'SYNC_STATE'}));
    expect((await recovered).state).toEqual(c.state);
    await new Promise(resolve=>setTimeout(resolve,moveA.durationMs+30));
    const manualRoll = receive(host,e=>e.type==='DICE_ROLLED');
    const manualState = receive(host,e=>e.type==='STATE' && e.state.version>c.state.version);
    host.send(JSON.stringify({type:'ROLL_DICE'}));
    expect((await manualRoll).timedOut).toBe(false);
    const selected = await manualState;
    expect(selected.state.phase).toBe('moving');
    expect(selected.state.timeoutLives[before.state.currentPlayer]).toBe(3);
    expect(selected.turnDeadline-selected.serverTime).toBeGreaterThanOrEqual(DICE_ROLL_MS+950);
    expect(selected.turnDeadline).toBeGreaterThan(c.turnDeadline);
  });
},15000);
it('auto-rolls a blocked number and passes without moving any pawn', async () => {
  await withMatch(1,async (host,friend,before)=>{
    const roll = receive(host,e=>e.type==='DICE_ROLLED');
    const states = [host,friend].map(socket=>receive(socket,e=>e.type==='STATE' && e.state.version>before.state.version));
    expect(await roll).toMatchObject({value:1,timedOut:true,skipped:true,automatic:false});
    const [a,b] = await Promise.all(states);
    expect(a.state).toEqual(b.state);
    expect(a.state.currentPlayer).toBe(before.state.players[1].id);
    expect(a.state.tokens).toEqual(before.state.tokens);
    expect(a.state.timeoutLives[before.state.currentPlayer]).toBe(4);
    expect(a.state.timeoutLives[before.state.players[1].id]).toBe(5);
    expect(a.state.phase).toBe('rolling');
    expect(a.state.dice).toBeNull();
    const late = receive(host,e=>e.type==='ERROR');
    host.send(JSON.stringify({type:'ROLL_DICE'}));
    expect((await late).message).toMatch(/animation|not your turn/);
  });
},10000);
it('spends the last dot without removing the player, allows manual play at zero, then removes on the next missed timer without rolling', async () => {
  await withMatch([6,6,6,1,1,1], async (host,friend,before) => {
    const rolls: any[][] = [[], []];
    const moves: any[] = [];
    const balances: number[] = [];
    const hostId = before.state.currentPlayer;
    let left = false;
    const listeners = [host,friend].map((socket,index) => {
      const listener = (raw: unknown) => {
        const event = JSON.parse(String(raw));
        if (event.type === 'DICE_ROLLED' && event.playerId === hostId) rolls[index].push(event);
        if (index === 0 && event.type === 'STATE') balances.push(event.state.timeoutLives[hostId]);
        if (index === 0 && event.type === 'TOKEN_MOVED') moves.push(event);
        if (index === 0 && event.type === 'LEFT_ROOM') left = true;
      };
      socket.on('message',listener);
      return listener;
    });
    try {
      const zero = await receive(host,e => e.type === 'STATE' && e.state.timeoutLives[hostId] === 0,15000);
      expect(rolls[0].map(event => event.value)).toEqual([6,6,5]);
      expect(rolls[1]).toEqual(rolls[0]);
      expect([...new Set(balances)]).toEqual([4,3,2,1,0]);
      expect(left).toBe(false);
      expect(zero.state.phase).toBe('rolling');
      expect(zero.state.players).toHaveLength(2);
      expect(zero.state.tokens).toHaveLength(8);
      expect(zero.state.currentPlayer).toBe(before.state.players[1].id);
      // Return the turn manually from the other player (one cannot leave base).
      await new Promise(resolve => setTimeout(resolve,DICE_ROLL_MS+5*240+30));
      const passed = receive(host,e => e.type === 'STATE' && e.state.version > zero.state.version);
      friend.send(JSON.stringify({type:'ROLL_DICE'}));
      const available = await passed;
      expect(available.state.currentPlayer).toBe(hostId);
      expect(available.state.timeoutLives[hostId]).toBe(0);
      // Zero dots still permit manual play; the sole legal move is automatic.
      await new Promise(resolve => setTimeout(resolve,DICE_ROLL_MS+30));
      const manual = receive(host,e => e.type === 'DICE_ROLLED');
      const played = receive(host,e => e.type === 'STATE' && e.state.version > available.state.version);
      host.send(JSON.stringify({type:'ROLL_DICE'}));
      expect(await manual).toMatchObject({value:1,timedOut:false});
      const active = await played;
      expect(left).toBe(false);
      expect(active.state.players).toHaveLength(2);
      expect(active.state.timeoutLives[hostId]).toBe(0);
      await new Promise(resolve => setTimeout(resolve,DICE_ROLL_MS+240+30));
      const next = receive(host,e => e.type === 'STATE' && e.state.version > active.state.version);
      friend.send(JSON.stringify({type:'ROLL_DICE'}));
      const waiting = await next;
      expect(waiting.state.currentPlayer).toBe(hostId);
      const removal = receive(host,e => e.type === 'LEFT_ROOM');
      const finished = receive(friend,e => e.type === 'STATE' && e.state.phase === 'finished');
      expect(await removal).toMatchObject({reason:'inactivity'});
      const final = await finished;
      expect(rolls[0].map(event => event.value)).toEqual([6,6,5,1]);
      expect(rolls[1]).toEqual(rolls[0]);
      expect(moves).toHaveLength(4); // The zero-life deadline made no roll or move.
      expect(final.state.version).toBe(waiting.state.version+1);
      expect(final.state.players).toHaveLength(1);
      expect(final.state.tokens).toHaveLength(4);
      expect(final.state.winner).toBe(before.state.players[1].id);
      expect(final.turnDeadline).toBe(0);
      const created = receive(host,e => e.type === 'ROOM_CREATED');
      host.send(JSON.stringify({type:'CREATE_ROOM',name:'Back again'}));
      expect((await created).roomCode).toBeTruthy();
    } finally {
      [host,friend].forEach((socket,index) => socket.off('message',listeners[index]));
    }
  });
},25000);

it('does not charge a life for a normal single-choice auto-move after a manual roll', async () => {
  await withMatch([6,1],async (host,friend,before) => {
    const selected = receive(host,e => e.type === 'STATE' && e.state.phase === 'moving');
    host.send(JSON.stringify({type:'ROLL_DICE'}));
    const first = await selected;
    expect(first.state.timeoutLives).toEqual(before.state.timeoutLives);
    await new Promise(resolve => setTimeout(resolve,DICE_ROLL_MS+30));
    const moved = receive(host,e => e.type === 'TOKEN_MOVED');
    const movedState = receive(host,e => e.type === 'STATE' && e.state.version > first.state.version);
    host.send(JSON.stringify({type:'MOVE_TOKEN',tokenId:before.state.tokens[0].id}));
    const movement = await moved;
    const after = await movedState;
    await new Promise(resolve => setTimeout(resolve,movement.durationMs+30));
    const automatic = receive(host,e => e.type === 'TOKEN_MOVED');
    const snapshots = [host,friend].map(socket => receive(socket,e => e.type === 'STATE' && e.state.version > after.state.version));
    host.send(JSON.stringify({type:'ROLL_DICE'}));
    expect(await automatic).toMatchObject({automatic:true,timedOut:false,from:1,to:2});
    for (const snapshot of await Promise.all(snapshots)) expect(snapshot.state.timeoutLives).toEqual(before.state.timeoutLives);
  });
},15000);

it('shares the two-sixes limit across manual and timeout rolls', async () => {
  await withMatch(6,async (host,friend,before) => {
    const first = receive(host,e => e.type === 'DICE_ROLLED');
    host.send(JSON.stringify({type:'ROLL_DICE'}));
    expect(await first).toMatchObject({value:6,timedOut:false});
    const moved = await receive(host,e => e.type === 'TOKEN_MOVED');
    expect(moved.timedOut).toBe(true);
    const second = await receive(host,e => e.type === 'DICE_ROLLED');
    expect(second).toMatchObject({value:6,timedOut:true});
    await new Promise(resolve => setTimeout(resolve,DICE_ROLL_MS+30));
    const move = receive(host,e => e.type === 'TOKEN_MOVED');
    host.send(JSON.stringify({type:'MOVE_TOKEN',tokenId:before.state.tokens[0].id}));
    const manualMove = await move;
    expect(manualMove.timedOut).toBe(false);
    await new Promise(resolve => setTimeout(resolve,manualMove.durationMs+30));
    const third = [host,friend].map(socket => receive(socket,e => e.type === 'DICE_ROLLED'));
    const snapshot = receive(host,e => e.type === 'STATE' && e.state.version > manualMove.version);
    host.send(JSON.stringify({type:'ROLL_DICE'}));
    for (const event of await Promise.all(third)) expect(event).toMatchObject({value:5,timedOut:false,playerId:before.state.currentPlayer});
    expect((await snapshot).state.timeoutLives[before.state.currentPlayer]).toBe(3);
  });
},15000);
