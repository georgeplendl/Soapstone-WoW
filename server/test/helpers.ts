import { SELF } from 'cloudflare:test'
import { solve } from '../src/auth'

export type Client = {
  id: string
  token: string
  call: (method: string, path: string, body?: unknown) => Promise<{ status: number; body: any }>
  push: (body: Record<string, unknown>) => Promise<any>
  pull: (zones: Record<number, number>, unlocks?: number) => Promise<any>
}

const BASE = 'https://soapstone.test'

export async function call(method: string, path: string, body?: unknown, headers: Record<string, string> = {}) {
  const res = await SELF.fetch(BASE + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  })
  return { status: res.status, body: (await res.json()) as any }
}

export async function newClient(): Promise<Client> {
  const ch = (await call('GET', '/v1/challenge')).body
  const reg = await call('POST', '/v1/register', { challenge: ch.challenge, nonce: await solve(ch.challenge, ch.bits) })
  if (reg.status !== 200) throw new Error(`register failed: ${JSON.stringify(reg.body)}`)
  const { installId: id, token } = reg.body
  const auth = { Authorization: `Bearer ${id}.${token}` }
  const client: Client = {
    id,
    token,
    call: (method, path, body) => call(method, path, body, auth),
    push: async (body) => {
      const res = await client.call('POST', '/v1/push', { flavor: 'forever', region: 'us', ...body })
      if (res.status !== 200) throw new Error(`push failed: ${res.status} ${JSON.stringify(res.body)}`)
      return res.body
    },
    pull: async (zones, unlocks = 0) => {
      const z = Object.entries(zones).map(([zone, since]) => `${zone}:${since}`).join(',')
      const res = await client.call('GET', `/v1/pull?flavor=forever&region=us&zones=${z}&unlocks=${unlocks}`)
      if (res.status !== 200) throw new Error(`pull failed: ${res.status} ${JSON.stringify(res.body)}`)
      return res.body
    },
  }
  return client
}

let n = 0
// A unique character name per call, so tests sharing a database never clash.
export function charKey(): string {
  n++
  return `Tester${n}-Stone${Math.random().toString(36).slice(2, 8)}`
}

let spot = 0
// A stone at a fresh spot (far from every other test's stones) unless overridden.
export function stone(authorKey: string, over: Record<string, unknown> = {}) {
  spot++
  return {
    id: `${authorKey}-1790000000-${spot}`,
    v: 1,
    authorKey,
    t: 1790000000,
    zone: 1411,
    instance: 1,
    wx: spot * 100,
    wy: -spot * 100,
    mapID: 1411,
    x: 0.5,
    y: 0.5,
    text: `Praise the sun ${spot}`,
    ...over,
  }
}
