// Checks for everything a client sends. Mirrors the addon's own rules
// (Soapstone/Codec.lua DecodeStone, WritePanel.MAX_LETTERS, Sketch.lua), so a
// stone the addon would refuse is refused here too. Anything odd is rejected
// rather than repaired.

export const MAX_LETTERS = 140
export const MAX_TEXT_BYTES = 600
export const MAX_SKETCH_CHARS = 8000
export const SKETCH_WIDTH = 160
export const SKETCH_HEIGHT = 60
const MAX_ID = 100
const MAX_KEY = 60
const MAX_COORD = 1_000_000

export const REGIONS = ['us', 'eu', 'kr', 'tw', 'cn'] as const

export type Sketch = { w: number; h: number; data: string }

// A stone as the addon stores it (SoapstoneDB.stones), minus local fields.
export type StoneIn = {
  id: string
  v: number
  authorKey: string
  t: number
  zone: number
  instance: number
  wx: number
  wy: number
  mapID?: number
  x?: number
  y?: number
  edited?: number
  text?: string
  sketch?: Sketch
}

export type DeleteIn = { id: string; v: number; deletedAt?: number }

type Result<T> = { ok: true; value: T } | { ok: false; reason: string }

const isInt = (n: unknown): n is number => typeof n === 'number' && Number.isInteger(n)
const isNum = (n: unknown): n is number => typeof n === 'number' && Number.isFinite(n)
const isStr = (s: unknown): s is string => typeof s === 'string'

export function isFlavor(s: unknown): s is string {
  return isStr(s) && /^(forever|retail|classic(-\d{1,3})?)$/.test(s)
}

export function isRegion(s: unknown): s is string {
  return isStr(s) && (REGIONS as readonly string[]).includes(s)
}

// "Mad-Decent" (Forever: first and last name) or "Mad-Stormrage"; the addon
// strips spaces and hyphens from the second part (Identity.Key).
export function isCharKey(s: unknown): s is string {
  return isStr(s) && s.length <= MAX_KEY && /^[^\s~;|%-]+(-[^\s~;|%-]+)?$/u.test(s)
}

// The addon's ids are "<authorKey>-<unix time>-<n>".
function idBelongsTo(id: string, authorKey: string): boolean {
  return id.length <= MAX_ID && id.startsWith(authorKey + '-') && id.length > authorKey.length + 1
}

// Letters, not bytes: the message box counts what you see.
function letters(s: string): number {
  return [...s].length
}

export function checkText(text: unknown): Result<string> {
  if (!isStr(text) || text === '') return { ok: false, reason: 'text' }
  if (new TextEncoder().encode(text).length > MAX_TEXT_BYTES || letters(text) > MAX_LETTERS) {
    return { ok: false, reason: 'text too long' }
  }
  // Control characters have no place in a one-box message (and \n is the
  // only one WoW's edit box could produce).
  if (/[\u0000-\u0009\u000b-\u001f\u007f]/.test(text)) return { ok: false, reason: 'text characters' }
  return { ok: true, value: text }
}

const SKETCH_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

// Sketch.lua packs alternating blank/ink run lengths as base-32 varints in a
// base64 alphabet. It must decode cleanly and not run past the grid.
export function checkSketch(sketch: unknown): Result<Sketch> {
  if (typeof sketch !== 'object' || sketch === null) return { ok: false, reason: 'sketch' }
  const { w, h, data } = sketch as Record<string, unknown>
  if (w !== SKETCH_WIDTH || h !== SKETCH_HEIGHT) return { ok: false, reason: 'sketch size' }
  if (!isStr(data) || data.length === 0 || data.length > MAX_SKETCH_CHARS || !/^[A-Za-z0-9+/]+$/.test(data)) {
    return { ok: false, reason: 'sketch data' }
  }
  let pos = 0
  let cells = 0
  while (pos < data.length) {
    let value = 0
    let scale = 1
    for (;;) {
      if (pos >= data.length) return { ok: false, reason: 'sketch decode' }
      const digit = SKETCH_ALPHABET.indexOf(data[pos++])
      value += (digit % 32) * scale
      if (digit < 32) break
      scale *= 32
      if (scale > 2 ** 40) return { ok: false, reason: 'sketch decode' }
    }
    cells += value
  }
  if (cells > w * h) return { ok: false, reason: 'sketch decode' }
  return { ok: true, value: { w, h, data } }
}

export function checkStone(raw: unknown): Result<StoneIn> {
  if (typeof raw !== 'object' || raw === null) return { ok: false, reason: 'stone' }
  const s = raw as Record<string, unknown>
  if (!isStr(s.id) || !isCharKey(s.authorKey) || !idBelongsTo(s.id, s.authorKey)) {
    return { ok: false, reason: 'id not the author\'s' }
  }
  if (!isInt(s.v) || s.v < 1 || s.v > 1_000_000) return { ok: false, reason: 'version' }
  if (!isInt(s.zone) || s.zone <= 0) return { ok: false, reason: 'zone' }
  if (!isInt(s.t) || s.t <= 0) return { ok: false, reason: 'drop time' }
  if (!isInt(s.instance) || !isNum(s.wx) || !isNum(s.wy)) return { ok: false, reason: 'position' }
  if (Math.abs(s.wx) > MAX_COORD || Math.abs(s.wy) > MAX_COORD) return { ok: false, reason: 'position' }
  if (s.mapID !== undefined && !isInt(s.mapID)) return { ok: false, reason: 'map' }
  for (const k of ['x', 'y'] as const) {
    if (s[k] !== undefined && (!isNum(s[k]) || (s[k] as number) < 0 || (s[k] as number) > 1)) {
      return { ok: false, reason: 'map position' }
    }
  }
  if (s.edited !== undefined && !isInt(s.edited)) return { ok: false, reason: 'edited' }

  const stone: StoneIn = {
    id: s.id, v: s.v, authorKey: s.authorKey, t: s.t, zone: s.zone, instance: s.instance,
    wx: s.wx, wy: s.wy, mapID: s.mapID as number | undefined, x: s.x as number | undefined,
    y: s.y as number | undefined, edited: s.edited as number | undefined,
  }
  if (s.text !== undefined && s.sketch !== undefined) return { ok: false, reason: 'kind' }
  if (s.text !== undefined) {
    const text = checkText(s.text)
    if (!text.ok) return text
    stone.text = text.value
  } else if (s.sketch !== undefined) {
    const sketch = checkSketch(s.sketch)
    if (!sketch.ok) return sketch
    stone.sketch = sketch.value
  } else {
    return { ok: false, reason: 'kind' }
  }
  return { ok: true, value: stone }
}

export function checkDelete(raw: unknown): Result<DeleteIn> {
  if (typeof raw !== 'object' || raw === null) return { ok: false, reason: 'delete' }
  const d = raw as Record<string, unknown>
  if (!isStr(d.id) || d.id.length > MAX_ID || !isInt(d.v) || d.v < 1 || d.v > 1_000_000) {
    return { ok: false, reason: 'delete' }
  }
  if (d.deletedAt !== undefined && !isInt(d.deletedAt)) return { ok: false, reason: 'delete' }
  return { ok: true, value: { id: d.id, v: d.v, deletedAt: d.deletedAt as number | undefined } }
}
