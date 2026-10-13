import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'tn.winnalkaw.app',
  appName: 'Win Nalkaw',
  webDir: 'dist',
  android: {
    // Keep the local app on Capacitor's HTTPS localhost origin.
    // Do not set server.url to the Netlify site: the app bundles its web UI.
    allowMixedContent: false,
  },
};

export default config;
