// Bindings and settings (wrangler.jsonc `vars`, secrets, .dev.vars).
// Every LIMIT_* has a default in code; set one only to change it.
export type Env = {
  DB: D1Database
  SERVER_SECRET: string           // signs challenges and hashes IPs (a secret)
  RL_IP?: RateLimit               // requests per minute per IP (wrangler.jsonc ratelimits)
  RL_INSTALL?: RateLimit          // requests per minute per install
  POW_BITS?: string               // proof-of-work difficulty
  LIMIT_REGISTER_PER_IP?: string  // new installs per IP per day
  LIMIT_CHARS_PER_INSTALL?: string // character names one install may own (per game type and region)
  EDIT_HOURS?: string             // how long after the server first sees a stone it may still be edited
  LIMIT_STONES_PER_INSTALL?: string
  LIMIT_STONES_PER_CHAR?: string
  LIMIT_EDITS_PER_INSTALL?: string
  LIMIT_VOTES_PER_INSTALL?: string
  LIMIT_UNLOCKS_PER_INSTALL?: string
  LIMIT_REPORTS_PER_INSTALL?: string
  LIMIT_LIVE_PER_CHAR_ZONE?: string
  LIMIT_STONES_PER_SPOT?: string
  REPORTS_TO_HIDE?: string
}
