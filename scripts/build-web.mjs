import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import dotenv from 'dotenv';

const root = fileURLToPath(new URL('../', import.meta.url));
const mobile = path.join(root, 'apps/mobile');
// Command/CI environment values take precedence over configuration files.
dotenv.config({ path: path.join(mobile, '.env.production.local'), quiet: true });
dotenv.config({ path: path.join(mobile, '.env.production'), quiet: true });

const value = process.env.EXPO_PUBLIC_REALTIME_URL?.trim();
let url;
try { url = new URL(value); } catch { /* Never echo possibly sensitive input. */ }
const host = url?.hostname.toLowerCase() || '';
const privateHost = /^(localhost|127\.|0\.0\.0\.0|10\.|192\.168\.|169\.254\.|172\.(1[6-9]|2\d|3[01])\.)/.test(host)
  || host.includes(':') || host.endsWith('.local');
const placeholder = /your[-_]|example|\.invalid$|\.test$/.test(host);
if (!url || url.protocol !== 'wss:' || url.username || url.password || privateHost || placeholder) {
  console.error('Production build needs a public wss:// game-server URL.');
  console.error('Set EXPO_PUBLIC_REALTIME_URL in your shell or apps/mobile/.env.production.local.');
  console.error('Local Wi-Fi addresses and example placeholders cannot be deployed.');
  process.exit(1);
}
process.env.EXPO_PUBLIC_REALTIME_URL = url.href;
if (process.argv.includes('--check')) {
  console.log('Production server URL format is valid (server availability not checked).');
  process.exit(0);
}
const command = process.platform === 'win32' ? 'npm.cmd' : 'npm';
const result = spawnSync(command, ['--prefix', mobile, 'run', 'build:web'], {
  cwd: root, env: process.env, stdio: 'inherit', shell: process.platform === 'win32',
});
if (result.error) { console.error('Could not start the Expo build:', result.error.message); process.exit(1); }
process.exit(result.status ?? 1);
