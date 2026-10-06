// POST /v1/push: everything a companion uploads for one game type and region.
//
// {
//   flavor: "forever", region: "us",
//   stones:  [stone],                               // new or edited (validate.ts StoneIn)
//   deletes: [{ id, v, authorKey, zone, deletedAt }],
//   votes:   [{ stoneId, charKey, value }],         // 1, -1, or 0 to take it back
//   unlocks: [{ stoneId, charKey, unlockedAt }],
//   reports: [{ stoneId, reason }],
// }
// -> { acks: { stones, deletes, votes, unlocks, reports }, rejected: [{ kind, id, reason, retry }] }
//
// Acked items are done; the addon clears them from `pending`. Rejected items
// won't go through as sent (`retry: true` means try again tomorrow).
//
// A stone that's well formed and really the author's, but refused (limits,
// word filter), is still recorded as "rejected" without its words, so players
// who got it live over the channel are told to remove it on their next pull.

import type { Install } from './auth'
import { sha256 } from './auth'
import type { Env } from './env'
import { checkDelete, checkStone, isCharKey, isFlavor, isRegion, type StoneIn } from './validate'
import { allow, HttpError, nextSeq, now } from './util'

const MAX = { stones: 100, deletes: 100, votes: 500, unlocks: 500, reports: 50 }
const SPOT_YARDS = 10

type Kind = keyof typeof MAX
type Rejection = { kind: Kind; id: string; reason: string; retry?: boolean }

type StoneRow = {
  id: string
  author_key: string
  install_id: string
  v: number
  status: string
  deleted_at: number | null
  zone: number
  score: number
  text: string | null
}

const setting = (env: Env, name: keyof Env, fallback: number): number => Number(env[name] ?? fallback)

export async function push(env: Env, install: Install, body: unknown) {
  const b = (body ?? {}) as Record<string, unknown>
  if (!isFlavor(b.flavor) || !isRegion(b.region)) throw new HttpError(400, 'bad_request', 'flavor and region are required')
  const flavor = b.flavor
  const region = b.region
  const list = (kind: Kind): unknown[] => {
    const value = b[kind] ?? []
    if (!Array.isArray(value)) throw new HttpError(400, 'bad_request', `${kind} must be a list`)
    if (value.length > MAX[kind]) throw new HttpError(413, 'too_many', `At most ${MAX[kind]} ${kind} per push`)
    return value
  }
  const input = { stones: list('stones'), deletes: list('deletes'), votes: list('votes'), unlocks: list('unlocks'), reports: list('reports') }

  const acks: Record<Kind, string[]> = { stones: [], deletes: [], votes: [], unlocks: [], reports: [] }
  const rejected: Rejection[] = []
  const reject = (kind: Kind, id: unknown, reason: string, retry = false) =>
    rejected.push({ kind, id: typeof id === 'string' ? id : '', reason, ...(retry ? { retry } : {}) })

  // Name ownership: the first install to write as a character owns it.
  const owned = new Map<string, boolean>()
  async function owns(charKey: string): Promise<boolean> {
    const known = owned.get(charKey)
    if (known !== undefined) return known
    const t = now()
    await env.DB.prepare(
      `INSERT INTO characters (flavor, region, char_key, install_id, claimed_at, last_seen) VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT (flavor, region, char_key) DO UPDATE SET last_seen = excluded.last_seen
       WHERE characters.install_id = excluded.install_id`,
    ).bind(flavor, region, charKey, install.id, t, t).run()
    const row = await env.DB.prepare('SELECT install_id FROM characters WHERE flavor = ? AND region = ? AND char_key = ?')
      .bind(flavor, region, charKey).first<{ install_id: string }>()
    const mine = row?.install_id === install.id
    owned.set(charKey, mine)
    return mine
  }

  const getStone = (id: string) =>
    env.DB.prepare('SELECT id, author_key, install_id, v, status, deleted_at, zone, score, text FROM stones WHERE flavor = ? AND region = ? AND id = ?')
      .bind(flavor, region, id).first<StoneRow>()

  const blocked = (await env.DB.prepare('SELECT word FROM blocked_words').all<{ word: string }>()).results.map((r) => r.word.toLowerCase())

  // Why a new (or re-tried) stone can't go live, or null if it can.
  async function refusal(stone: StoneIn): Promise<{ reason: string; retry?: boolean } | null> {
    if (!(await allow(env, install.id, 'stones', setting(env, 'LIMIT_STONES_PER_INSTALL', 30)))) return { reason: 'too many stones today', retry: true }
    if (!(await allow(env, `char:${flavor}:${region}:${stone.authorKey}`, 'stones', setting(env, 'LIMIT_STONES_PER_CHAR', 10)))) {
      return { reason: 'too many stones today', retry: true }
    }
    if (stone.text !== undefined) {
      const lower = stone.text.toLowerCase()
      if (blocked.some((word) => lower.includes(word))) return { reason: 'word filter' }
      const dup = await env.DB.prepare(
        `SELECT 1 FROM stones WHERE install_id = ? AND text = ? AND created_at > ? AND id != ? AND status = 'live' AND deleted_at IS NULL LIMIT 1`,
      ).bind(install.id, stone.text, now() - 86400, stone.id).first()
      if (dup) return { reason: 'duplicate' }
    }
    const inZone = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM stones WHERE flavor = ? AND region = ? AND author_key = ? AND zone = ? AND id != ?
       AND status = 'live' AND deleted_at IS NULL`,
    ).bind(flavor, region, stone.authorKey, stone.zone, stone.id).first<{ n: number }>()
    if ((inZone?.n ?? 0) >= setting(env, 'LIMIT_LIVE_PER_CHAR_ZONE', 10)) return { reason: 'too many in this zone' }
    const nearby = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM stones WHERE flavor = ? AND region = ? AND instance = ? AND id != ?
       AND wx BETWEEN ? AND ? AND wy BETWEEN ? AND ? AND status = 'live' AND deleted_at IS NULL`,
    ).bind(flavor, region, stone.instance, stone.id, stone.wx - SPOT_YARDS, stone.wx + SPOT_YARDS, stone.wy - SPOT_YARDS, stone.wy + SPOT_YARDS)
      .first<{ n: number }>()
    if ((nearby?.n ?? 0) >= setting(env, 'LIMIT_STONES_PER_SPOT', 3)) return { reason: 'too many nearby' }
    return null
  }

  async function saveSketch(stone: StoneIn): Promise<string | null> {
    if (!stone.sketch) return null
    const id = 'sk_' + (await sha256(stone.sketch.data)).slice(0, 16)
    await env.DB.prepare('INSERT OR IGNORE INTO sketches (id, w, h, data, created_at) VALUES (?, ?, ?, ?, ?)')
      .bind(id, stone.sketch.w, stone.sketch.h, stone.sketch.data, now()).run()
    return id
  }

  async function writeStone(stone: StoneIn, status: 'live' | 'rejected', reason: string | null) {
    const live = status === 'live'
    const sketchId = live ? await saveSketch(stone) : null
    await env.DB.prepare(
      `INSERT INTO stones (flavor, region, id, author_key, zone, instance, wx, wy, map_id, x, y, kind, text, sketch_id,
         v, t, edited, status, reason, install_id, created_at, updated_seq)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT (flavor, region, id) DO UPDATE SET
         zone = excluded.zone, instance = excluded.instance, wx = excluded.wx, wy = excluded.wy,
         map_id = excluded.map_id, x = excluded.x, y = excluded.y, kind = excluded.kind, text = excluded.text,
         sketch_id = excluded.sketch_id, v = excluded.v, t = excluded.t, edited = excluded.edited,
         status = excluded.status, reason = excluded.reason, updated_seq = excluded.updated_seq`,
    ).bind(
      flavor, region, stone.id, stone.authorKey, stone.zone, stone.instance, stone.wx, stone.wy,
      stone.mapID ?? null, stone.x ?? null, stone.y ?? null,
      live ? (stone.sketch ? 'sketch' : 'text') : null, live ? stone.text ?? null : null, sketchId,
      stone.v, stone.t, stone.edited ?? null, status, reason, install.id, now(), await nextSeq(env),
    ).run()
  }

  // An edit changes only the words or drawing; the stone stays where it was.
  async function editStone(stone: StoneIn) {
    await env.DB.prepare(
      `UPDATE stones SET kind = ?, text = ?, sketch_id = ?, v = ?, edited = ?, updated_seq = ?
       WHERE flavor = ? AND region = ? AND id = ?`,
    ).bind(stone.sketch ? 'sketch' : 'text', stone.text ?? null, await saveSketch(stone), stone.v, stone.edited ?? now(),
      await nextSeq(env), flavor, region, stone.id).run()
  }

  async function bump(stoneId: string, set: string, ...params: unknown[]) {
    await env.DB.prepare(`UPDATE stones SET ${set}, updated_seq = ? WHERE flavor = ? AND region = ? AND id = ?`)
      .bind(...params, await nextSeq(env), flavor, region, stoneId).run()
  }

  // Stones ------------------------------------------------------------------
  for (const raw of input.stones) {
    const checked = checkStone(raw)
    if (!checked.ok) { reject('stones', (raw as { id?: unknown })?.id, checked.reason); continue }
    const stone = checked.value
    if (!(await owns(stone.authorKey))) { reject('stones', stone.id, 'name belongs to another install'); continue }

    const existing = await getStone(stone.id)
    if (existing && existing.install_id !== install.id) { reject('stones', stone.id, 'not yours'); continue }
    if (existing?.deleted_at) { reject('stones', stone.id, 'deleted'); continue }

    if (existing && existing.status !== 'rejected') {
      if (stone.v <= existing.v) { acks.stones.push(stone.id); continue } // already have it
      if (existing.status === 'hidden') { reject('stones', stone.id, 'hidden'); continue }
      if (stone.text !== undefined && blocked.some((word) => stone.text!.toLowerCase().includes(word))) {
        reject('stones', stone.id, 'word filter'); continue
      }
      if (!(await allow(env, install.id, 'edits', setting(env, 'LIMIT_EDITS_PER_INSTALL', 60)))) {
        reject('stones', stone.id, 'too many edits today', true); continue
      }
      await editStone(stone)
      acks.stones.push(stone.id)
      continue
    }

    // New, or a rejected stone tried again.
    const no = await refusal(stone)
    if (no) {
      // Record the refusal (no words) so live copies get removed; capped so
      // a flood of refused stones can't fill the table.
      if (await allow(env, install.id, 'rejected', 100)) await writeStone(stone, 'rejected', no.reason)
      reject('stones', stone.id, no.reason, no.retry)
      continue
    }
    await writeStone(stone, 'live', null)
    acks.stones.push(stone.id)
  }

  // Deletes -----------------------------------------------------------------
  for (const raw of input.deletes) {
    const checked = checkDelete(raw)
    if (!checked.ok) { reject('deletes', (raw as { id?: unknown })?.id, checked.reason); continue }
    const del = checked.value
    const r = raw as Record<string, unknown>
    const existing = await getStone(del.id)
    if (existing) {
      if (existing.install_id !== install.id) { reject('deletes', del.id, 'not yours'); continue }
      if (!existing.deleted_at) {
        await bump(del.id, 'kind = NULL, text = NULL, sketch_id = NULL, deleted_at = ?, v = MAX(v, ?)', del.deletedAt ?? now(), del.v)
      }
      acks.deletes.push(del.id)
      continue
    }
    // Never uploaded (dropped and deleted between syncs), but players may have
    // it from the live channel: leave a tombstone so their copies go too.
    const authorKey = r.authorKey
    const zone = r.zone
    if (!isCharKey(authorKey) || !del.id.startsWith(authorKey + '-') || !Number.isInteger(zone) || (zone as number) <= 0) {
      reject('deletes', del.id, 'unknown stone; authorKey and zone needed'); continue
    }
    if (!(await owns(authorKey))) { reject('deletes', del.id, 'name belongs to another install'); continue }
    await env.DB.prepare(
      `INSERT INTO stones (flavor, region, id, author_key, zone, v, deleted_at, install_id, created_at, updated_seq)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).bind(flavor, region, del.id, authorKey, zone, del.v, del.deletedAt ?? now(), install.id, now(), await nextSeq(env)).run()
    acks.deletes.push(del.id)
  }

  // Votes -------------------------------------------------------------------
  for (const raw of input.votes) {
    const { stoneId, charKey, value } = (raw ?? {}) as Record<string, unknown>
    const key = `${String(stoneId)}|${String(charKey)}`
    if (typeof stoneId !== 'string' || !isCharKey(charKey) || ![1, -1, 0].includes(value as number)) { reject('votes', key, 'vote'); continue }
    if (!(await owns(charKey))) { reject('votes', key, 'name belongs to another install'); continue }
    const stone = await getStone(stoneId)
    if (!stone || stone.deleted_at || stone.status !== 'live') { acks.votes.push(key); continue } // nothing to vote on any more
    if (stone.install_id === install.id) { reject('votes', key, 'own stone'); continue }
    const prev = await env.DB.prepare('SELECT value FROM votes WHERE flavor = ? AND region = ? AND stone_id = ? AND char_key = ?')
      .bind(flavor, region, stoneId, charKey).first<{ value: number }>()
    const delta = (value as number) - (prev?.value ?? 0)
    if (delta === 0) { acks.votes.push(key); continue }
    if (!(await allow(env, install.id, 'votes', setting(env, 'LIMIT_VOTES_PER_INSTALL', 200)))) { reject('votes', key, 'too many votes today', true); continue }
    if (value === 0) {
      await env.DB.prepare('DELETE FROM votes WHERE flavor = ? AND region = ? AND stone_id = ? AND char_key = ?')
        .bind(flavor, region, stoneId, charKey).run()
    } else {
      await env.DB.prepare(
        `INSERT INTO votes (flavor, region, stone_id, char_key, value, install_id, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT (flavor, region, stone_id, char_key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`,
      ).bind(flavor, region, stoneId, charKey, value, install.id, now()).run()
    }
    await bump(stoneId, 'score = score + ?', delta)
    acks.votes.push(key)
  }

  // Unlocks -----------------------------------------------------------------
  // Self-reported, so an honour system: fine for a character's own progress
  // and found counts, never proof for anything competitive.
  for (const raw of input.unlocks) {
    const { stoneId, charKey, unlockedAt } = (raw ?? {}) as Record<string, unknown>
    const key = `${String(stoneId)}|${String(charKey)}`
    if (typeof stoneId !== 'string' || !isCharKey(charKey) || !Number.isInteger(unlockedAt) || (unlockedAt as number) <= 0) {
      reject('unlocks', key, 'unlock'); continue
    }
    if (!(await owns(charKey))) { reject('unlocks', key, 'name belongs to another install'); continue }
    const stone = await getStone(stoneId)
    if (!stone || stone.status === 'rejected') { reject('unlocks', key, 'unknown stone'); continue }
    const prev = await env.DB.prepare('SELECT unlocked_at FROM unlocks WHERE flavor = ? AND region = ? AND char_key = ? AND stone_id = ?')
      .bind(flavor, region, charKey, stoneId).first<{ unlocked_at: number }>()
    if (prev) {
      // Keep the earliest unlock time either side has.
      if ((unlockedAt as number) < prev.unlocked_at) {
        await env.DB.prepare('UPDATE unlocks SET unlocked_at = ?, updated_seq = ? WHERE flavor = ? AND region = ? AND char_key = ? AND stone_id = ?')
          .bind(unlockedAt, await nextSeq(env), flavor, region, charKey, stoneId).run()
      }
      acks.unlocks.push(key)
      continue
    }
    if (!(await allow(env, install.id, 'unlocks', setting(env, 'LIMIT_UNLOCKS_PER_INSTALL', 2000)))) { reject('unlocks', key, 'too many unlocks today', true); continue }
    await env.DB.prepare(
      'INSERT INTO unlocks (flavor, region, char_key, stone_id, unlocked_at, install_id, updated_seq) VALUES (?, ?, ?, ?, ?, ?, ?)',
    ).bind(flavor, region, charKey, stoneId, unlockedAt, install.id, await nextSeq(env)).run()
    // Finding your own stones (any of this install's characters) doesn't count.
    if (stone.install_id !== install.id) await bump(stoneId, 'found_count = found_count + 1')
    acks.unlocks.push(key)
  }

  // Reports -----------------------------------------------------------------
  for (const raw of input.reports) {
    const { stoneId, reason } = (raw ?? {}) as Record<string, unknown>
    if (typeof stoneId !== 'string' || (reason !== undefined && (typeof reason !== 'string' || reason.length > 200))) {
      reject('reports', stoneId, 'report'); continue
    }
    const stone = await getStone(stoneId)
    if (!stone || stone.status !== 'live' || stone.deleted_at) { acks.reports.push(stoneId); continue }
    if (stone.install_id === install.id) { reject('reports', stoneId, 'own stone'); continue }
    if (!(await allow(env, install.id, 'reports', setting(env, 'LIMIT_REPORTS_PER_INSTALL', 20)))) { reject('reports', stoneId, 'too many reports today', true); continue }
    await env.DB.prepare('INSERT OR IGNORE INTO reports (flavor, region, stone_id, install_id, reason, created_at) VALUES (?, ?, ?, ?, ?, ?)')
      .bind(flavor, region, stoneId, install.id, reason ?? null, now()).run()
    const reporters = await env.DB.prepare('SELECT COUNT(*) AS n FROM reports WHERE flavor = ? AND region = ? AND stone_id = ?')
      .bind(flavor, region, stoneId).first<{ n: number }>()
    if ((reporters?.n ?? 0) >= setting(env, 'REPORTS_TO_HIDE', 3)) await bump(stoneId, "status = 'hidden'")
    acks.reports.push(stoneId)
  }

  return { acks, rejected }
}
