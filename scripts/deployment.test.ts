import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { expect, it } from 'vitest';

it('Firebase deploys only the current Expo web output', () => {
  const config = JSON.parse(readFileSync('firebase.json', 'utf8'));
  expect(config.hosting.public).toBe('apps/mobile/dist');
  expect(config.hosting.rewrites).toEqual([{ source: '**', destination: '/index.html' }]);
});
it('production validation rejects missing, local, insecure and placeholder endpoints', () => {
  for (const url of ['', 'ws://192.168.1.10:8787', 'wss://localhost:8787', 'wss://192.168.1.10:8787', 'https://server.onrender.com', 'wss://YOUR_SERVER.onrender.com']) {
    const result = spawnSync(process.execPath, ['scripts/build-web.mjs', '--check'], { env: { ...process.env, EXPO_PUBLIC_REALTIME_URL: url }, encoding: 'utf8' });
    expect(result.status, url).toBe(1);
    expect(result.stderr).toContain('public wss://');
  }
});
it('accepts a public secure URL without deploying anything', () => {
  const result = spawnSync(process.execPath, ['scripts/build-web.mjs', '--check'], { env: { ...process.env, EXPO_PUBLIC_REALTIME_URL: 'wss://rally-ludo-server.onrender.com' }, encoding: 'utf8' });
  expect(result.status).toBe(0);
  expect(result.stdout).toContain('availability not checked');
});
