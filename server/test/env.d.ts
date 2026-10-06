import type { D1Migration } from 'cloudflare:test'
import type { Env as ServerEnv } from '../src/env'

// What `env` from cloudflare:test holds in tests: the server's bindings plus
// the migrations vitest.config.ts passes in.
declare global {
  namespace Cloudflare {
    interface Env extends ServerEnv {
      TEST_MIGRATIONS: D1Migration[]
    }
  }
}
