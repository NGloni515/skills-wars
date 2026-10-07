import { defineConfig } from 'vitest/config';
import tsconfigPaths from 'vite-tsconfig-paths';

export default defineConfig({
  plugins: [tsconfigPaths()],
  test: {
    globals: true,
    root: './',
    include: ['**/*.e2e-spec.ts'],
    env: {
      NODE_ENV: 'test',
      MATCH_SERVER_COMMAND: 'fake-godot',
      MATCH_SECRET: 'test-secret-0123456789',
      PUBLIC_HOST: 'play.example.test',
      MATCH_PORT_MIN: '7800',
      MATCH_PORT_MAX: '7801',
      MATCH_START_TIMEOUT_MS: '1000',
    },
  },
});
