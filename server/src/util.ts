import type { Env } from './env'

export class HttpError extends Error {
  constructor(public status: number, public code: string, message: string, public retryAfter?: number) {
    super(message)
  }
}

export const now = (): number => Math.floor(Date.now() / 1000)
const DAY = 86400
export const today = (): number => Math.floor(now() / DAY)
const secondsToMidnight = (): number => DAY - (now() % DAY)

// Counts one more `kind` for `subject` today and returns the new count.
export async function count(env: Env, subject: string, kind: string): Promise<number> {
  const row = await env.DB.prepare(
    `INSERT INTO usage (subject, day, kind, n) VALUES (?, ?, ?, 1)
     ON CONFLICT (subject, day, kind) DO UPDATE SET n = n + 1 RETURNING n`,
  ).bind(subject, today(), kind).first<{ n: number }>()
  return row?.n ?? 1
}

// Like count, but throws 429 once today's count passes `max`.
export async function limit(env: Env, subject: string, kind: string, max: number): Promise<void> {
  if ((await count(env, subject, kind)) > max) {
    throw new HttpError(429, 'rate_limited', `Too many ${kind} today`, secondsToMidnight())
  }
}

// Whether `subject` may do one more `kind` today; counts it if so.
export async function allow(env: Env, subject: string, kind: string, max: number): Promise<boolean> {
  return (await count(env, subject, kind)) <= max
}

export async function nextSeq(env: Env): Promise<number> {
  const row = await env.DB.prepare(
    "UPDATE counters SET value = value + 1 WHERE name = 'seq' RETURNING value",
  ).first<{ value: number }>()
  if (!row) throw new Error('counters.seq missing')
  return row.value
}

export function json(body: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...headers },
  })
}
