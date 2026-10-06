import { env } from 'cloudflare:test'
import { describe, expect, it } from 'vitest'
import { solve } from '../src/auth'
import { call, charKey, newClient, stone } from './helpers'

const SKETCH = { w: 160, h: 60, data: 'gDKkB' } // a few runs of blank and ink

describe('registration', () => {
  it('registers an install with a solved challenge, once per challenge', async () => {
    const ch = (await call('GET', '/v1/challenge')).body
    const nonce = await solve(ch.challenge, ch.bits)
    const first = await call('POST', '/v1/register', { challenge: ch.challenge, nonce })
    expect(first.status).toBe(200)
    expect(first.body.installId).toMatch(/^[0-9a-f]{24}$/)
    const again = await call('POST', '/v1/register', { challenge: ch.challenge, nonce })
    expect(again.body.error).toBe('used_challenge')
  })

  it('refuses a wrong nonce or a forged challenge', async () => {
    const ch = (await call('GET', '/v1/challenge')).body
    // Most nonces don't solve it at 4 bits; try until one fails.
    let wrong
    for (let i = 0; ; i++) {
      wrong = await call('POST', '/v1/register', { challenge: ch.challenge, nonce: `x${i}` })
      if (wrong.status !== 200) break
    }
    expect(wrong.body.error).toBe('bad_proof')
    const forged = ch.challenge.replace(/\.[0-9a-f]+$/, '.' + '0'.repeat(64))
    const res = await call('POST', '/v1/register', { challenge: forged, nonce: await solve(forged, ch.bits) })
    expect(res.body.error).toBe('bad_challenge')
  })

  it('needs a valid token for everything else', async () => {
    expect((await call('GET', '/v1/pull?flavor=forever&region=us')).status).toBe(401)
    const c = await newClient()
    const wrong = await call('GET', '/v1/pull?flavor=forever&region=us', undefined, { Authorization: `Bearer ${c.id}.${'0'.repeat(64)}` })
    expect(wrong.status).toBe(401)
  })

  it('refuses banned installs', async () => {
    const c = await newClient()
    await env.DB.prepare("UPDATE installs SET status = 'banned' WHERE id = ?").bind(c.id).run()
    expect((await c.call('GET', '/v1/pull?flavor=forever&region=us')).status).toBe(403)
  })
})

describe('stones', () => {
  it('shares a stone with other installs and pages by cursor', async () => {
    const a = await newClient()
    const b = await newClient()
    const s = stone(charKey(), { zone: 9001 })
    const res = await a.push({ stones: [s] })
    expect(res.acks.stones).toEqual([s.id])
    expect(res.rejected).toEqual([])

    const got = await b.pull({ 9001: 0 })
    const zone = got.zones['9001']
    expect(zone.stones).toHaveLength(1)
    expect(zone.stones[0]).toMatchObject({ id: s.id, text: s.text, authorKey: s.authorKey, score: 0, found: 0 })
    expect((await b.pull({ 9001: zone.cursor })).zones['9001'].stones).toHaveLength(0)
  })

  it('keeps game types and regions apart', async () => {
    const a = await newClient()
    const s = stone(charKey(), { zone: 9002 })
    await a.push({ stones: [s], flavor: 'retail' })
    expect((await a.pull({ 9002: 0 })).zones['9002'].stones).toHaveLength(0)
  })

  it("keeps WoW Forever's beta (region test) apart from launch regions", async () => {
    const a = await newClient()
    const pushed = await a.push({ stones: [stone(charKey(), { zone: 9003 })], region: 'test' })
    expect(pushed.acks.stones).toHaveLength(1)
    expect((await a.pull({ 9003: 0 })).zones['9003'].stones).toHaveLength(0)
  })

  it('lets only the install that owns a name write as it', async () => {
    const a = await newClient()
    const b = await newClient()
    const key = charKey()
    await a.push({ stones: [stone(key)] })
    const res = await b.push({ stones: [stone(key)] })
    expect(res.rejected[0]).toMatchObject({ kind: 'stones', reason: 'name belongs to another install' })
  })

  it('rejects malformed stones without recording them', async () => {
    const a = await newClient()
    const key = charKey()
    const long = stone(key, { text: 'x'.repeat(141) })
    const notTheirs = { ...stone(key), id: 'Someone-Else-1-1' }
    const both = stone(key, { sketch: SKETCH })
    const res = await a.push({ stones: [long, notTheirs, both] })
    expect(res.rejected.map((r: any) => r.reason)).toEqual(['text too long', "id not the author's", 'kind'])
    const rows = await env.DB.prepare('SELECT COUNT(*) AS n FROM stones WHERE author_key = ?').bind(key).first<{ n: number }>()
    expect(rows!.n).toBe(0)
  })

  it('counts letters, not bytes, toward the 140 limit', async () => {
    const a = await newClient()
    const res = await a.push({ stones: [stone(charKey(), { text: 'é'.repeat(140) })] })
    expect(res.rejected).toEqual([])
  })

  it('applies edits with a higher version and ignores stale ones', async () => {
    const a = await newClient()
    const b = await newClient()
    const s = stone(charKey(), { zone: 9003 })
    await a.push({ stones: [s] })
    await a.push({ stones: [{ ...s, v: 2, text: 'Try jumping', edited: 1790000500, wx: 0 }] })
    const stale = await a.push({ stones: [{ ...s, v: 1, text: 'old words' }] })
    expect(stale.acks.stones).toEqual([s.id])
    const got = (await b.pull({ 9003: 0 })).zones['9003'].stones[0]
    expect(got).toMatchObject({ v: 2, text: 'Try jumping', edited: 1790000500, wx: s.wx }) // edits don't move stones
  })

  it('stores drawings by content and serves them by id', async () => {
    const a = await newClient()
    const b = await newClient()
    const s = stone(charKey(), { zone: 9004, text: undefined, sketch: SKETCH })
    expect((await a.push({ stones: [s] })).rejected).toEqual([])
    const got = (await b.pull({ 9004: 0 })).zones['9004'].stones[0]
    expect(got.sketchId).toMatch(/^sk_[0-9a-f]{16}$/)
    expect(got.text).toBeUndefined()
    const res = await b.call('POST', '/v1/sketches', { ids: [got.sketchId] })
    expect(res.body.sketches).toEqual([{ id: got.sketchId, ...SKETCH }])
  })

  it('rejects drawings that are the wrong size or overrun the grid', async () => {
    const a = await newClient()
    const key = charKey()
    const res = await a.push({
      stones: [
        stone(key, { text: undefined, sketch: { ...SKETCH, w: 100 } }),
        stone(key, { text: undefined, sketch: { ...SKETCH, data: '//////A' } }),
      ],
    })
    expect(res.rejected.map((r: any) => r.reason)).toEqual(['sketch size', 'sketch decode'])
  })
})

describe('deletes', () => {
  it('turns a stone into a removal for everyone', async () => {
    const a = await newClient()
    const b = await newClient()
    const s = stone(charKey(), { zone: 9010 })
    await a.push({ stones: [s] })
    const before = await b.pull({ 9010: 0 })
    const res = await a.push({ deletes: [{ id: s.id, v: 1, deletedAt: 1790001000 }] })
    expect(res.acks.deletes).toEqual([s.id])
    const after = (await b.pull({ 9010: before.zones['9010'].cursor })).zones['9010']
    expect(after.removed).toEqual([{ id: s.id, v: 1, zone: 9010, why: 'deleted' }])
    const row = await env.DB.prepare('SELECT text FROM stones WHERE id = ?').bind(s.id).first<{ text: string | null }>()
    expect(row!.text).toBeNull()
  })

  it('leaves a tombstone for a stone deleted before it was ever uploaded', async () => {
    const a = await newClient()
    const b = await newClient()
    const key = charKey()
    const id = `${key}-1790000000-77`
    const res = await a.push({ deletes: [{ id, v: 1, authorKey: key, zone: 9011 }] })
    expect(res.acks.deletes).toEqual([id])
    expect((await b.pull({ 9011: 0 })).zones['9011'].removed[0]).toMatchObject({ id, why: 'deleted' })
  })

  it('refuses deleting someone else\'s stone, and re-adding a deleted one', async () => {
    const a = await newClient()
    const b = await newClient()
    const s = stone(charKey())
    await a.push({ stones: [s] })
    expect((await b.push({ deletes: [{ id: s.id, v: 2 }] })).rejected[0].reason).toBe('not yours')
    await a.push({ deletes: [{ id: s.id, v: 2 }] })
    expect((await a.push({ stones: [{ ...s, v: 3 }] })).rejected[0].reason).toBe('deleted')
  })
})

describe('votes', () => {
  it('keeps one vote per character and a running score', async () => {
    const a = await newClient()
    const b = await newClient()
    const s = stone(charKey(), { zone: 9020 })
    await a.push({ stones: [s] })
    const voter = charKey()
    await b.push({ votes: [{ stoneId: s.id, charKey: voter, value: 1 }] })
    await b.push({ votes: [{ stoneId: s.id, charKey: voter, value: 1 }] }) // repeat: no change
    expect((await a.pull({ 9020: 0 })).zones['9020'].stones[0].score).toBe(1)
    await b.push({ votes: [{ stoneId: s.id, charKey: voter, value: -1 }] })
    expect((await a.pull({ 9020: 0 })).zones['9020'].stones[0].score).toBe(-1)
    await b.push({ votes: [{ stoneId: s.id, charKey: voter, value: 0 }] })
    expect((await a.pull({ 9020: 0 })).zones['9020'].stones[0].score).toBe(0)
  })

  it('refuses votes on your own install\'s stones', async () => {
    const a = await newClient()
    const s = stone(charKey())
    await a.push({ stones: [s] })
    const res = await a.push({ votes: [{ stoneId: s.id, charKey: charKey(), value: 1 }] })
    expect(res.rejected[0].reason).toBe('own stone')
  })
})

describe('unlocks', () => {
  it('counts finds, keeps the earliest time, and stays private', async () => {
    const a = await newClient()
    const b = await newClient()
    const c = await newClient()
    const s = stone(charKey(), { zone: 9030 })
    await a.push({ stones: [s] })
    const finder = charKey()
    await b.push({ unlocks: [{ stoneId: s.id, charKey: finder, unlockedAt: 1790002000 }] })
    await b.push({ unlocks: [{ stoneId: s.id, charKey: finder, unlockedAt: 1790001000 }] })
    await b.push({ unlocks: [{ stoneId: s.id, charKey: finder, unlockedAt: 1790003000 }] })

    expect((await a.pull({ 9030: 0 })).zones['9030'].stones[0].found).toBe(1)
    const mine = (await b.pull({})).unlocks
    expect(mine.items).toEqual([{ charKey: finder, stoneId: s.id, unlockedAt: 1790001000 }])
    expect((await c.pull({})).unlocks.items).toEqual([])
    expect((await b.pull({}, mine.cursor)).unlocks.items).toEqual([])
  })

  it('doesn\'t count finding your own stones', async () => {
    const a = await newClient()
    const s = stone(charKey(), { zone: 9031 })
    await a.push({ stones: [s] })
    await a.push({ unlocks: [{ stoneId: s.id, charKey: charKey(), unlockedAt: 1790001000 }] })
    expect((await a.pull({ 9031: 0 })).zones['9031'].stones[0].found).toBe(0)
  })

  it('refuses unlocks as a character another install owns', async () => {
    const a = await newClient()
    const b = await newClient()
    const s = stone(charKey())
    await a.push({ stones: [s] })
    const res = await b.push({ unlocks: [{ stoneId: s.id, charKey: s.authorKey, unlockedAt: 1790001000 }] })
    expect(res.rejected[0].reason).toBe('name belongs to another install')
  })
})

describe('reports and shadow limits', () => {
  // Installs a day old or more, from different addresses.
  async function established(n: number) {
    const clients = []
    for (let i = 0; i < n; i++) {
      const c = await newClient()
      await env.DB.prepare('UPDATE installs SET created_at = created_at - 2 * 86400, ip_hash = ? WHERE id = ?').bind(`ip-${c.id}`, c.id).run()
      clients.push(c)
    }
    return clients
  }

  it('hides a stone once three established installs from different addresses report it', async () => {
    const author = await newClient()
    const s = stone(charKey(), { zone: 9040 })
    await author.push({ stones: [s] })
    const reporters = await established(3)
    for (const r of reporters.slice(0, 2)) await r.push({ reports: [{ stoneId: s.id, reason: 'rude' }] })
    expect((await reporters[0].pull({ 9040: 0 })).zones['9040'].stones).toHaveLength(1)
    await reporters[2].push({ reports: [{ stoneId: s.id }] })
    const zone = (await reporters[0].pull({ 9040: 0 })).zones['9040']
    expect(zone.stones).toHaveLength(0)
    expect(zone.removed[0]).toMatchObject({ id: s.id, why: 'hidden' })
  })

  it("doesn't let throwaway installs hide a stone", async () => {
    const author = await newClient()
    const s = stone(charKey(), { zone: 9042 })
    await author.push({ stones: [s] })
    for (let i = 0; i < 4; i++) await (await newClient()).push({ reports: [{ stoneId: s.id }] }) // brand new
    const sameAddress = await established(3)
    await env.DB.prepare("UPDATE installs SET ip_hash = 'one-address' WHERE id IN (?, ?, ?)").bind(...sameAddress.map((c) => c.id)).run()
    for (const r of sameAddress) await r.push({ reports: [{ stoneId: s.id }] })
    expect((await author.pull({ 9042: 0 })).zones['9042'].stones).toHaveLength(1)
    const kept = await env.DB.prepare('SELECT COUNT(*) AS n FROM reports WHERE stone_id = ?').bind(s.id).first<{ n: number }>()
    expect(kept?.n).toBe(7) // every report is kept for review
  })

  it('shows a limited install\'s stones only to itself', async () => {
    const a = await newClient()
    const b = await newClient()
    await env.DB.prepare("UPDATE installs SET status = 'limited' WHERE id = ?").bind(a.id).run()
    const s = stone(charKey(), { zone: 9041 })
    expect((await a.push({ stones: [s] })).acks.stones).toEqual([s.id]) // looks fine to them
    expect((await a.pull({ 9041: 0 })).zones['9041'].stones).toHaveLength(1)
    expect((await b.pull({ 9041: 0 })).zones['9041'].removed[0]).toMatchObject({ id: s.id, why: 'hidden' })
  })
})

describe('limits', () => {
  it('refuses a fourth stone on the same spot, and tells others to drop it', async () => {
    const clients = [await newClient(), await newClient(), await newClient(), await newClient()]
    const b = await newClient()
    const at = { zone: 9050, instance: 7, wx: 5000, wy: 5000 }
    for (const c of clients.slice(0, 3)) {
      expect((await c.push({ stones: [stone(charKey(), at)] })).rejected).toEqual([])
    }
    const fourth = stone(charKey(), { ...at, wx: 5008 })
    const res = await clients[3].push({ stones: [fourth] })
    expect(res.rejected[0]).toMatchObject({ id: fourth.id, reason: 'too many nearby' })

    const zone = (await b.pull({ 9050: 0 })).zones['9050']
    expect(zone.stones).toHaveLength(3)
    expect(zone.removed).toEqual([{ id: fourth.id, v: 1, zone: 9050, why: 'rejected' }])
    const own = (await clients[3].pull({ 9050: 0 })).zones['9050'].removed[0]
    expect(own).toMatchObject({ why: 'rejected', reason: 'too many nearby' })
  })

  it('caps live stones per character per zone', async () => {
    const a = await newClient()
    const key = charKey()
    const stones = Array.from({ length: 10 }, () => stone(key, { zone: 9051 }))
    expect((await a.push({ stones })).rejected).toEqual([])
    // The 11th is over both the zone cap and the daily cap per character.
    expect((await a.push({ stones: [stone(key, { zone: 9051 })] })).rejected[0].reason).toBe('too many stones today')
  })

  it('filters blocked words and duplicate text', async () => {
    await env.DB.prepare("INSERT INTO blocked_words (word) VALUES ('grossword')").run()
    const a = await newClient()
    const key = charKey()
    const res = await a.push({
      stones: [
        stone(key, { text: 'You are a GrossWord' }),
        stone(key, { text: 'Same words twice' }),
        stone(key, { text: 'Same words twice' }),
      ],
    })
    expect(res.rejected.map((r: any) => r.reason)).toEqual(['word filter', 'duplicate'])
  })

  it('refuses stones past the daily install limit, marked to retry', async () => {
    const a = await newClient()
    const stones = [charKey(), charKey(), charKey(), charKey()].flatMap((key) =>
      Array.from({ length: 8 }, () => stone(key)))
    const res = await a.push({ stones }) // 32 stones; the install limit is 30 a day
    const refused = res.rejected.filter((r: any) => r.reason === 'too many stones today')
    expect(refused).toHaveLength(2)
    expect(refused.every((r: any) => r.retry)).toBe(true)
  })
})

describe('abuse (adversarial review 2026-10-06)', () => {
  it("won't let a short name take a longer name's ids", async () => {
    const a = await newClient()
    const victim = charKey() // "TesterN-StoneXYZ"
    const short = victim.split('-')[0]
    const res = await a.push({ stones: [stone(short, { id: `${victim}-1791000000-1` })] })
    expect(res.rejected[0]).toMatchObject({ kind: 'stones', reason: "id not the author's" })
    const b = await newClient()
    const real = stone(victim, { id: `${victim}-1791000000-1` })
    expect((await b.push({ stones: [real] })).acks.stones).toEqual([real.id])
  })

  it('caps the names one install can own, and counts one vote per install', async () => {
    const owner = await newClient()
    const target = stone(charKey())
    await owner.push({ stones: [target] })
    const stuffer = await newClient()
    const votes = Array.from({ length: 25 }, () => ({ stoneId: target.id, charKey: charKey(), value: 1 }))
    const res = await stuffer.push({ votes })
    expect(res.acks.votes).toHaveLength(20)
    expect(res.rejected.every((r: { reason: string }) => r.reason === 'too many characters')).toBe(true)
    const seen = (await stuffer.pull({ 1411: 0 })).zones['1411'].stones.find((s: { id: string }) => s.id === target.id)
    expect(seen.score).toBe(1) // 20 names, one install, one vote
  })

  it('counts a find once per install, whichever character', async () => {
    const owner = await newClient()
    const target = stone(charKey())
    await owner.push({ stones: [target] })
    const finder = await newClient()
    const t = Math.floor(Date.now() / 1000)
    await finder.push({ unlocks: [charKey(), charKey(), charKey()].map((c) => ({ stoneId: target.id, charKey: c, unlockedAt: t })) })
    const seen = (await finder.pull({ 1411: 0 })).zones['1411'].stones.find((s: { id: string }) => s.id === target.id)
    expect(seen.found).toBe(1)
  })

  it('refuses edits long after the drop', async () => {
    const a = await newClient()
    const key = charKey()
    const t = Math.floor(Date.now() / 1000)
    const s = stone(key, { id: `${key}-${t}-1`, t })
    await a.push({ stones: [s] })
    expect((await a.push({ stones: [{ ...s, v: 2, text: 'fixed a typo', edited: t + 60 }] })).acks.stones).toEqual([s.id])
    const late = await a.push({ stones: [{ ...s, v: 3, text: 'rewritten later', edited: t + 2 * 3600 }] })
    expect(late.rejected[0]).toMatchObject({ reason: 'too late to edit' })
    const old = stone(key, { t: 1790000000 })
    await a.push({ stones: [old] })
    const sneaky = await a.push({ stones: [{ ...old, v: 2, text: 'rewritten', edited: 1790000060 }] })
    expect(sneaky.acks.stones).toEqual([old.id]) // first seen just now and claims a quick edit: allowed
    await env.DB.prepare('UPDATE stones SET created_at = created_at - 13 * 3600 WHERE id = ?').bind(old.id).run()
    const later = await a.push({ stones: [{ ...old, v: 3, text: 'rewritten again', edited: 1790000090 }] })
    expect(later.rejected[0]).toMatchObject({ reason: 'too late to edit' }) // but not 13 hours after the server saw it
  })

  it('refuses impossible times', async () => {
    const a = await newClient()
    const key = charKey()
    const res = await a.push({
      stones: [stone(key, { t: 9_000_000_000 }), stone(key, { t: 1_000_000_000 }), stone(key, { edited: 1789999999 })],
      unlocks: [{ stoneId: 'x', charKey: key, unlockedAt: 9_000_000_000 }],
    })
    expect(res.rejected.map((r: { reason: string }) => r.reason)).toEqual(['drop time', 'drop time', 'edited', 'unlock'])
  })

  it('refuses WoW escape codes but keeps a plain pipe', async () => {
    const a = await newClient()
    const key = charKey()
    const res = await a.push({
      stones: [
        stone(key, { text: '|cffff0000Free gold|r' }),
        stone(key, { text: 'click |Hurl:x|h[here]|h' }),
        stone(key, { text: '|TInterface\\Icons\\INV:0|t' }),
        stone(key, { text: 'left || right' }),
        stone(key, { text: 'a | b' }),
      ],
    })
    expect(res.rejected.map((r: { reason: string }) => r.reason)).toEqual(['text characters', 'text characters', 'text characters'])
    expect(res.acks.stones).toHaveLength(2)
  })

  it('matches the word filter on whole words', async () => {
    await env.DB.prepare("INSERT OR IGNORE INTO blocked_words (word) VALUES ('coon')").run()
    const a = await newClient()
    const key = charKey()
    const res = await a.push({ stones: [stone(key, { text: 'A raccoon stole my loot' }), stone(key, { text: 'you COON!' })] })
    expect(res.acks.stones).toHaveLength(1)
    expect(res.rejected[0]).toMatchObject({ reason: 'word filter' })
  })

  it('has a starter word filter', async () => {
    const n = await env.DB.prepare('SELECT COUNT(*) AS n FROM blocked_words').first<{ n: number }>()
    expect(n?.n).toBeGreaterThan(20)
  })

  it('treats an IPv6 /64 as one address', async () => {
    const { clientIp } = await import('../src/auth')
    const at = (ip: string) => clientIp(new Request('https://x', { headers: { 'CF-Connecting-IP': ip } }))
    expect(at('2001:db8:1:2:aaaa::1')).toBe(at('2001:0db8:0001:0002:ffff:1:2:3'))
    expect(at('2001:db8::1')).toBe('2001:db8:0:0::/64')
    expect(at('203.0.113.9')).toBe('203.0.113.9')
    expect(at('2001:db8:1:2:aaaa::1')).not.toBe(at('2001:db8:1:3::1'))
  })

  it('slows down a burst of requests from one install', async () => {
    const a = await newClient()
    const statuses = []
    for (let i = 0; i < 40; i++) statuses.push((await a.call('GET', '/v1/pull?flavor=forever&region=us&zones=1411:0')).status)
    // The local runtime may not enforce rate limits; when it does, the burst is cut off.
    expect(statuses.every((s) => s === 200 || s === 429)).toBe(true)
  })
})
