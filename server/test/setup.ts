import { applyD1Migrations, env } from 'cloudflare:test'

// Each test file gets its own database; bring it up to the latest schema.
await applyD1Migrations(env.DB, env.TEST_MIGRATIONS)
