// Soapstone server: the database behind the companion app.
// Design: docs/Ideas/Idea - Companion App (WoW).md.
//
//   GET  /v1/challenge   proof-of-work puzzle for registering
//   POST /v1/register    solved puzzle -> install id + token
//   POST /v1/push        stones, deletes, votes, unlocks, reports
//   GET  /v1/pull        changes per zone since a cursor, and your unlocks
//   POST /v1/sketches    drawings by id
//
// Everything but challenge and register needs "Authorization: Bearer <id>.<token>".

import { authenticate, challenge, clientIp, register, sha256 } from './auth'
import type { Env } from './env'
import { pull, sketches } from './pull'
import { push } from './push'
import { HttpError, json } from './util'

const MAX_BODY = 1_000_000

async function readJson(request: Request): Promise<unknown> {
  const text = await request.text()
  if (text.length > MAX_BODY) throw new HttpError(413, 'too_large', 'Request body too large')
  try {
    return JSON.parse(text)
  } catch {
    throw new HttpError(400, 'bad_json', 'Body is not JSON')
  }
}

// Per-minute request limits, before any database work. A refused request
// is cheap, but on Workers it still counts toward the daily request quota;
// only a firewall rule in front of the Worker can stop those (see README).
async function throttle(limiter: RateLimit | undefined, key: string): Promise<void> {
  if (limiter && !(await limiter.limit({ key })).success) {
    throw new HttpError(429, 'slow_down', 'Too many requests; try again in a minute', 60)
  }
}

async function byIp(request: Request, env: Env): Promise<void> {
  const ip = clientIp(request)
  if (ip !== 'local') await throttle(env.RL_IP, await sha256(`ip:${ip}`))
}

async function signedIn(request: Request, env: Env) {
  const install = await authenticate(request, env)
  await throttle(env.RL_INSTALL, install.id)
  return install
}

async function route(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url)
  const at = `${request.method} ${url.pathname}`
  switch (at) {
    case 'GET /v1/challenge':
      await byIp(request, env)
      return json(await challenge(env))
    case 'POST /v1/register':
      await byIp(request, env)
      return json(await register(request, env, await readJson(request)))
    case 'POST /v1/push':
      return json(await push(env, await signedIn(request, env), await readJson(request)))
    case 'GET /v1/pull':
      return json(await pull(env, await signedIn(request, env), url))
    case 'POST /v1/sketches':
      await signedIn(request, env)
      return json(await sketches(env, await readJson(request)))
    default:
      throw new HttpError(404, 'not_found', `No route for ${at}`)
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      return await route(request, env)
    } catch (err) {
      if (err instanceof HttpError) {
        const headers: Record<string, string> = err.retryAfter ? { 'Retry-After': String(err.retryAfter) } : {}
        return json({ error: err.code, message: err.message }, err.status, headers)
      }
      console.error(err)
      return json({ error: 'internal', message: 'Something went wrong' }, 500)
    }
  },
} satisfies ExportedHandler<Env>
