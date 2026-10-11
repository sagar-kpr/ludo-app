import { spawn } from 'node:child_process';
import { createServer } from 'node:net';

const probe = createServer();
await new Promise(resolve => probe.listen(0, '127.0.0.1', resolve));
const port = probe.address().port;
await new Promise(resolve => probe.close(resolve));
const server = spawn(process.execPath, ['--import', 'tsx', 'apps/game-server/src/index.ts'], {
  env: { ...process.env, PORT: String(port), SUPABASE_SERVICE_ROLE_KEY: '' },
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
  const runner = spawn(process.execPath, ['scripts/godot.mjs', 'test', `--server=ws://127.0.0.1:${port}`], { stdio: 'inherit' });
  const timer = setTimeout(() => runner.kill(), 150000);
  const code = await new Promise(resolve => runner.once('exit', resolve));
  clearTimeout(timer);
  process.exitCode = code ?? 1;
} finally {
  server.kill();
}
