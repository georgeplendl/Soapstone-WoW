import path from 'node:path'
import { cloudflareTest, readD1Migrations } from '@cloudflare/vitest-pool-workers'
import { defineConfig } from 'vitest/config'

export default defineConfig({
  plugins: [
    cloudflareTest(async () => ({
      wrangler: { configPath: './wrangler.jsonc' },
      miniflare: {
        bindings: {
          SERVER_SECRET: 'test-secret',
          POW_BITS: '4',
          LIMIT_REGISTER_PER_IP: '1000',
          TEST_MIGRATIONS: await readD1Migrations(path.resolve('migrations')),
        },
      },
    })),
  ],
  test: {
    setupFiles: ['./test/setup.ts'],
  },
})
