import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  testMatch: '**/*.pw.ts',
  timeout: 60000,
  workers: 1,
  use: { launchOptions: { executablePath: process.env.CHROME_PATH || '/usr/bin/google-chrome' }, headless: true, viewport: { width: 430, height: 900 } },
  webServer: [
    { command: 'npm run server:start', url: 'http://127.0.0.1:19551', env: { PORT: '19551', SUPABASE_SERVICE_ROLE_KEY: '' } },
    { command: 'npx vite --host 127.0.0.1 --port 4173 --strictPort', url: 'http://127.0.0.1:4173', env: { VITE_REALTIME_URL: 'ws://127.0.0.1:19551' } },
    { command: 'npx vite apps/mobile/dist-e2e --host 127.0.0.1 --port 4174 --strictPort', url: 'http://127.0.0.1:4174' },
  ],
});
