import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.rallyludo.app',
  appName: 'Rally Ludo',
  webDir: 'dist',
  bundledWebRuntime: false,
  server: { androidScheme: 'https' },
};

export default config;
