// Bindings and settings (wrangler.jsonc `vars`, secrets, .dev.vars).
// Every LIMIT_* has a default in code; set one only to change it.
export type Env = {
  DB: D1Database
  SERVER_SECRET: string           // signs challenges and hashes IPs (a secret)
  POW_BITS?: string               // proof-of-work difficulty
  LIMIT_REGISTER_PER_IP?: string  // new installs per IP per day
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
