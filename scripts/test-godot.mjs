import { spawn } from 'node:child_process';
import { createServer } from 'node:net';

const livesTest = process.argv[2] === 'lives';
const computerTest = process.argv[2] === 'computer';
// Child-only deterministic dice exercise five combined roll/move timeouts.
const preload = 'data:text/javascript;base64,' + Buffer.from("import crypto from 'node:crypto'; import {syncBuiltinESMExports} from 'node:module'; crypto.randomInt=(min,max)=>min===1?max-1:0; syncBuiltinESMExports();").toString('base64');
const computerPreload = 'data:text/javascript;base64,' + Buffer.from("import crypto from 'node:crypto'; import {syncBuiltinESMExports} from 'node:module'; const values=[1,6,6,5]; let index=0; crypto.randomInt=(min,max)=>min===1?Math.min(values[Math.min(index++,3)],max-1):0; syncBuiltinESMExports();").toString('base64');
const probe = createServer();
await new Promise(resolve => probe.listen(0, '127.0.0.1', resolve));
const port = probe.address().port;
await new Promise(resolve => probe.close(resolve));
const server = spawn(process.execPath, ['--import', 'tsx', ...(livesTest ? ['--import',preload] : computerTest ? ['--import',computerPreload] : []), 'apps/game-server/src/index.ts'], {
  env: { ...process.env, PORT: String(port), SUPABASE_SERVICE_ROLE_KEY: '', ...(livesTest ? {TURN_TIMEOUT_MS:'1000'} : {}) },
  stdio: ['ignore', 'pipe', 'pipe'],
});
try {
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Test server startup timed out')), 15000);
    server.stdout.on('data', data => {
      if (String(data).includes('listening')) { clearTimeout(timer); resolve(); }
    });
    server.once('error', error => { clearTimeout(timer); reject(error); });
    server.once('exit', code => { clearTimeout(timer); reject(new Error(`Server exited: ${code}`)); });
  });
  const runner = spawn(process.execPath, ['scripts/godot.mjs', livesTest ? 'test:lives' : computerTest ? 'test:computer' : process.argv[2] === 'recovery' ? 'test:recovery' : process.argv[2] === 'leaving' ? 'test:leaving' : 'test', `--server=ws://127.0.0.1:${port}`], { stdio: 'inherit' });
  const timer = setTimeout(() => runner.kill(), 150000);
  const code = await new Promise(resolve => runner.once('exit', resolve));
  clearTimeout(timer);
  process.exitCode = code ?? 1;
} finally {
  server.kill();
}
