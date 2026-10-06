// Installs: anonymous registration with a proof-of-work puzzle, and the
// bearer token every later request carries.
//
//   GET  /v1/challenge  -> { challenge, bits }
//   POST /v1/register   { challenge, nonce } -> { installId, token }
//
// The puzzle: find a nonce so SHA-256("<challenge>:<nonce>") starts with
// `bits` zero bits. About a second of CPU for one install, expensive for a
// script registering thousands. Challenges are signed by the server, expire
// after 10 minutes, and each one registers at most one install (the install
// id is derived from it).

import type { Env } from './env'
import { HttpError, limit, now } from './util'

const CHALLENGE_TTL = 10 * 60

const encoder = new TextEncoder()

function hex(bytes: ArrayBuffer | Uint8Array): string {
  return [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, '0')).join('')
}

export async function sha256(text: string): Promise<string> {
  return hex(await crypto.subtle.digest('SHA-256', encoder.encode(text)))
}

async function hmac(secret: string, text: string): Promise<string> {
  const key = await crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
  return hex(await crypto.subtle.sign('HMAC', key, encoder.encode(text)))
}

function randomHex(bytes: number): string {
  return hex(crypto.getRandomValues(new Uint8Array(bytes)))
}

function leadingZeroBits(hexDigest: string): number {
  let bits = 0
  for (const ch of hexDigest) {
    const n = parseInt(ch, 16)
    if (n === 0) { bits += 4; continue }
    return bits + Math.clz32(n) - 28
  }
  return bits
}

// Constant-time comparison of two hex strings.
function sameHex(a: string, b: string): boolean {
  if (a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return diff === 0
}

export function powBits(env: Env): number {
  return Number(env.POW_BITS ?? 18)
}

export async function challenge(env: Env): Promise<{ challenge: string; bits: number }> {
  const body = `${now()}.${randomHex(12)}`
  return { challenge: `${body}.${await hmac(env.SERVER_SECRET, body)}`, bits: powBits(env) }
}

// Solves a challenge. Used by tests and scripts; the companion does the same.
export async function solve(challengeText: string, bits: number): Promise<string> {
  for (let nonce = 0; ; nonce++) {
    if (leadingZeroBits(await sha256(`${challengeText}:${nonce}`)) >= bits) return String(nonce)
  }
}

function clientIp(request: Request): string {
  return request.headers.get('CF-Connecting-IP') ?? 'local'
}

export async function register(request: Request, env: Env, body: unknown): Promise<{ installId: string; token: string }> {
  const { challenge: text, nonce } = (body ?? {}) as Record<string, unknown>
  if (typeof text !== 'string' || typeof nonce !== 'string' || nonce.length > 32) {
    throw new HttpError(400, 'bad_request', 'challenge and nonce are required')
  }
  const parts = text.split('.')
  if (parts.length !== 3) throw new HttpError(400, 'bad_challenge', 'Malformed challenge')
  const [issued, rand, sig] = parts
  if (!sameHex(sig, await hmac(env.SERVER_SECRET, `${issued}.${rand}`))) {
    throw new HttpError(400, 'bad_challenge', 'Challenge was not issued by this server')
  }
  if (now() - Number(issued) > CHALLENGE_TTL) throw new HttpError(400, 'expired_challenge', 'Challenge expired; ask for a new one')
  if (leadingZeroBits(await sha256(`${text}:${nonce}`)) < powBits(env)) {
    throw new HttpError(400, 'bad_proof', 'Nonce does not solve the challenge')
  }

  const ipHash = await hmac(env.SERVER_SECRET, `ip:${clientIp(request)}`)
  await limit(env, ipHash, 'register', Number(env.LIMIT_REGISTER_PER_IP ?? 5))

  const installId = (await sha256(`install:${text}`)).slice(0, 24)
  const token = randomHex(32)
  const inserted = await env.DB.prepare(
    'INSERT OR IGNORE INTO installs (id, token_hash, ip_hash, created_at) VALUES (?, ?, ?, ?)',
  ).bind(installId, await sha256(token), ipHash, now()).run()
  if (!inserted.meta.changes) throw new HttpError(400, 'used_challenge', 'Challenge already used')
  return { installId, token }
}

export type Install = { id: string; status: string }

// "Authorization: Bearer <installId>.<token>"
export async function authenticate(request: Request, env: Env): Promise<Install> {
  const header = request.headers.get('Authorization') ?? ''
  const match = /^Bearer ([0-9a-f]{24})\.([0-9a-f]{64})$/.exec(header)
  if (!match) throw new HttpError(401, 'unauthorized', 'Missing or malformed token')
  const row = await env.DB.prepare('SELECT id, token_hash, status FROM installs WHERE id = ?')
    .bind(match[1]).first<{ id: string; token_hash: string; status: string }>()
  if (!row || !sameHex(row.token_hash, await sha256(match[2]))) {
    throw new HttpError(401, 'unauthorized', 'Unknown install or wrong token')
  }
  if (row.status === 'banned') throw new HttpError(403, 'banned', 'This install is banned')
  return { id: row.id, status: row.status }
}
