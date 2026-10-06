// End-to-end check against a running server, acting as two companions:
// register both, drop a stone as one, pull it as the other, unlock it.
//
//   npm run dev                                  # in one terminal
//   node scripts/smoke.mjs                       # in another
//   node scripts/smoke.mjs https://soapstone-server.<you>.workers.dev
import { createHash } from 'node:crypto'

const base = process.argv[2] ?? 'http://localhost:8787'

const sha256 = (text) => createHash('sha256').update(text).digest('hex')

function zeroBits(hex) {
  let bits = 0
  for (const ch of hex) {
    const n = parseInt(ch, 16)
    if (n === 0) { bits += 4; continue }
    return bits + Math.clz32(n) - 28
  }
  return bits
}

async function call(method, path, body, auth) {
  const res = await fetch(base + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...(auth ? { Authorization: `Bearer ${auth}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  })
  const json = await res.json()
  if (!res.ok) throw new Error(`${method} ${path}: ${res.status} ${JSON.stringify(json)}`)
  return json
}

async function register() {
  const { challenge, bits } = await call('GET', '/v1/challenge')
  const started = Date.now()
  let nonce = 0
  while (zeroBits(sha256(`${challenge}:${nonce}`)) < bits) nonce++
  const { installId, token } = await call('POST', '/v1/register', { challenge, nonce: String(nonce) })
  console.log(`registered ${installId} (${bits}-bit proof of work in ${Date.now() - started} ms)`)
  return `${installId}.${token}`
}

const a = await register()
const b = await register()
const author = `Smoke${Date.now() % 100000}-Test`
const stone = {
  id: `${author}-${Math.floor(Date.now() / 1000)}-1`, v: 1, authorKey: author, t: Math.floor(Date.now() / 1000),
  zone: 1411, instance: 1, wx: Math.random() * 10000, wy: Math.random() * 10000, mapID: 1411, x: 0.5, y: 0.5,
  text: 'Praise the sun!',
}
const pushed = await call('POST', '/v1/push', { flavor: 'forever', region: 'us', stones: [stone] }, a)
console.log('push:', JSON.stringify(pushed))

const pulled = await call('GET', '/v1/pull?flavor=forever&region=us&zones=1411:0', undefined, b)
const found = pulled.zones['1411'].stones.find((s) => s.id === stone.id)
console.log('pull as the other install:', found ? `found "${found.text}"` : 'NOT FOUND')

await call('POST', '/v1/push', {
  flavor: 'forever', region: 'us',
  unlocks: [{ stoneId: stone.id, charKey: `Finder${Date.now() % 100000}-Test`, unlockedAt: Math.floor(Date.now() / 1000) }],
}, b)
const again = await call('GET', '/v1/pull?flavor=forever&region=us&zones=1411:0', undefined, a)
console.log('found count after unlock:', again.zones['1411'].stones.find((s) => s.id === stone.id)?.found)
if (!found) process.exit(1)
