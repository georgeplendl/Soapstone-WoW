// GET /v1/pull?flavor=forever&region=us&zones=1411:0,1412:57&unlocks=0
//
// `zones` lists each zone with the highest change number (cursor) already
// seen there; 0 for a zone never pulled. `unlocks` is the cursor for this
// install's own characters' unlocks.
//
// -> {
//   zones: { "1411": { stones: [...], removed: [...], cursor, more } },
//   unlocks: { items: [{ charKey, stoneId, unlockedAt }], cursor, more },
// }
//
// `removed` entries are { id, v, zone, why }: "deleted" (the author removed
// it), "hidden" (reported, or its install is limited) or "rejected" (never
// shared). The addon removes a stone only on one of these, never just because
// a pull didn't mention it. Your own hidden or rejected stones come back as
// removals too, so the addon can mark them "not shared" and keep them.

import type { Install } from './auth'
import type { Env } from './env'
import { isFlavor, isRegion } from './validate'
import { HttpError } from './util'

const MAX_ZONES = 50
const PAGE = 500
const UNLOCK_PAGE = 1000

type Row = {
  id: string
  author_key: string
  zone: number
  instance: number | null
  wx: number | null
  wy: number | null
  map_id: number | null
  x: number | null
  y: number | null
  kind: string | null
  text: string | null
  sketch_id: string | null
  v: number
  t: number | null
  edited: number | null
  deleted_at: number | null
  status: string
  reason: string | null
  install_id: string
  install_status: string
  score: number
  found_count: number
  updated_seq: number
}

function parseZones(param: string | null): [number, number][] {
  if (!param) return []
  const zones = param.split(',').map((part) => {
    const m = /^(\d{1,7}):(\d{1,15})$/.exec(part)
    if (!m) throw new HttpError(400, 'bad_request', `Bad zone "${part}"; expected zone:cursor`)
    return [Number(m[1]), Number(m[2])] as [number, number]
  })
  if (zones.length > MAX_ZONES) throw new HttpError(400, 'too_many', `At most ${MAX_ZONES} zones per pull`)
  return zones
}

function stoneOut(r: Row) {
  return {
    id: r.id, v: r.v, authorKey: r.author_key, t: r.t, zone: r.zone, instance: r.instance,
    wx: r.wx, wy: r.wy, mapID: r.map_id ?? undefined, x: r.x ?? undefined, y: r.y ?? undefined,
    edited: r.edited ?? undefined,
    ...(r.kind === 'sketch' ? { sketchId: r.sketch_id } : { text: r.text }),
    score: r.score, found: r.found_count,
  }
}

export async function pull(env: Env, install: Install, url: URL) {
  const flavor = url.searchParams.get('flavor')
  const region = url.searchParams.get('region')
  if (!isFlavor(flavor) || !isRegion(region)) throw new HttpError(400, 'bad_request', 'flavor and region are required')
  const zones = parseZones(url.searchParams.get('zones'))
  const unlockCursor = Number(url.searchParams.get('unlocks') ?? 0)
  if (!Number.isSafeInteger(unlockCursor) || unlockCursor < 0) throw new HttpError(400, 'bad_request', 'Bad unlocks cursor')

  const out: Record<string, { stones: unknown[]; removed: unknown[]; cursor: number; more: boolean }> = {}
  for (const [zone, since] of zones) {
    const rows = (await env.DB.prepare(
      `SELECT s.*, i.status AS install_status FROM stones s JOIN installs i ON i.id = s.install_id
       WHERE s.flavor = ? AND s.region = ? AND s.zone = ? AND s.updated_seq > ?
       ORDER BY s.updated_seq LIMIT ?`,
    ).bind(flavor, region, zone, since, PAGE + 1).all<Row>()).results
    const more = rows.length > PAGE
    const page = rows.slice(0, PAGE)
    const stones: unknown[] = []
    const removed: unknown[] = []
    for (const r of page) {
      const mine = r.install_id === install.id
      if (r.deleted_at) removed.push({ id: r.id, v: r.v, zone: r.zone, why: 'deleted' })
      else if (r.status === 'rejected') {
        // Others only need to drop any live copy; the author learns why.
        removed.push({ id: r.id, v: r.v, zone: r.zone, why: 'rejected', ...(mine ? { reason: r.reason } : {}) })
      } else if (r.status !== 'live' || (r.install_status !== 'ok' && !mine)) {
        // Shadow limits: a limited install's stones look fine to itself only.
        removed.push({ id: r.id, v: r.v, zone: r.zone, why: 'hidden' })
      } else stones.push(stoneOut(r))
    }
    out[zone] = { stones, removed, cursor: page.length ? page[page.length - 1].updated_seq : since, more }
  }

  // Unlocks are private: only for characters this install owns.
  const unlockRows = (await env.DB.prepare(
    `SELECT u.char_key, u.stone_id, u.unlocked_at, u.updated_seq FROM unlocks u
     JOIN characters c ON c.flavor = u.flavor AND c.region = u.region AND c.char_key = u.char_key
     WHERE c.install_id = ? AND u.flavor = ? AND u.region = ? AND u.updated_seq > ?
     ORDER BY u.updated_seq LIMIT ?`,
  ).bind(install.id, flavor, region, unlockCursor, UNLOCK_PAGE + 1).all<{ char_key: string; stone_id: string; unlocked_at: number; updated_seq: number }>()).results
  const unlockPage = unlockRows.slice(0, UNLOCK_PAGE)

  return {
    zones: out,
    unlocks: {
      items: unlockPage.map((u) => ({ charKey: u.char_key, stoneId: u.stone_id, unlockedAt: u.unlocked_at })),
      cursor: unlockPage.length ? unlockPage[unlockPage.length - 1].updated_seq : unlockCursor,
      more: unlockRows.length > UNLOCK_PAGE,
    },
  }
}

// POST /v1/sketches { ids: ["sk_..."] } -> { sketches: [{ id, w, h, data }] }
export async function sketches(env: Env, body: unknown) {
  const ids = (body as { ids?: unknown })?.ids
  if (!Array.isArray(ids) || ids.length > 100 || !ids.every((id) => typeof id === 'string' && /^sk_[0-9a-f]{16}$/.test(id))) {
    throw new HttpError(400, 'bad_request', 'ids: up to 100 sketch ids')
  }
  if (!ids.length) return { sketches: [] }
  const rows = (await env.DB.prepare(`SELECT id, w, h, data FROM sketches WHERE id IN (${ids.map(() => '?').join(',')})`)
    .bind(...ids).all<{ id: string; w: number; h: number; data: string }>()).results
  return { sketches: rows }
}
