# Soapstone server

The database behind the Soapstone companion app: a Cloudflare Worker with a
D1 (SQLite) database. The design, and the reasons behind it, are in
[`docs/Ideas/Idea - Companion App (WoW).md`](../docs/Ideas/Idea%20-%20Companion%20App%20(WoW).md).

## API (v1)

Every request but `challenge` and `register` sends
`Authorization: Bearer <installId>.<token>`. Errors are
`{ error, message }` with an HTTP status; `429` comes with `Retry-After`.

| Endpoint | Does |
|---|---|
| `GET /v1/challenge` | A proof-of-work puzzle: `{ challenge, bits }` |
| `POST /v1/register` | `{ challenge, nonce }` → `{ installId, token }`. No account; one install per solved challenge |
| `POST /v1/push` | Stones, deletes, votes, unlocks and reports for one game type and region → acks and rejections |
| `GET /v1/pull` | `?flavor&region&zones=1411:0,1412:57&unlocks=0` → changed stones and removals per zone since each cursor, and this install's own unlocks |
| `POST /v1/sketches` | `{ ids }` → drawings |

The request and response shapes are documented at the top of
[`src/push.ts`](src/push.ts) and [`src/pull.ts`](src/pull.ts).

**Rules the server enforces, whatever the client says:**

- **Requests:** 20 a minute per IP for the puzzle and sign-up (an IPv6 /64
  counts as one address), 30 a minute per install for everything else
  (`ratelimits` in `wrangler.jsonc`, counted per Cloudflare location).
- **Names:** the first install to write as a character (`Mad-Decent`) owns
  it; nobody else can post, edit, delete, vote or unlock as it. One install
  owns at most 20 names (`LIMIT_CHARS_PER_INSTALL`).
- **Validation:** the addon's own rules (`Soapstone/Codec.lua`): ids are
  exactly `<author>-<time>-<n>`, text 1–140 letters with no WoW escape
  codes (`|c`, `|H`, `|T`...; `||` is a plain pipe), sketches 160×60 that
  decode cleanly, sane positions, and times from 2025 to a day ahead.
- **Edits:** only within 12 hours of the server first seeing a stone
  (`EDIT_HOURS`), and only if the edit claims to be within an hour of the
  drop (the addon allows 5 minutes).
- **Limits per day:** 30 new stones per install and 10 per character, 60
  edits, 200 votes, 2,000 unlocks, 20 reports, 5 new installs per IP.
- **One vote and one find per install** per stone, whichever character.
- **Density:** 10 live stones per character per zone; 3 stones within 10
  yards of each other.
- **Word filter** (`blocked_words`, whole words; a starter list of slurs
  in `migrations/0002_word_filter.sql`) and duplicate text within a day.
- **Reports:** every report is kept; reports from 3 installs that are at
  least a day old, in good standing and on different addresses hide a
  stone.
- **Shadow limits:** a `limited` install's stones are shown only to itself.
- **Unlocks are private:** only the owning install downloads them; others see
  a stone's found count.

Limits can be changed with the `LIMIT_*` settings in [`src/env.ts`](src/env.ts).

**What the code can't stop:** a refused request still counts toward the
Workers plan's daily request budget (100,000 on the free plan), so a flood
can use it up and stop sharing until midnight UTC. Blocking floods before
they reach the Worker needs a Cloudflare firewall rate-limiting rule, which
needs the server on a custom domain. See [SECURITY.md](../SECURITY.md).

## Working on it

Needs **Node.js 22** or newer (Wrangler requires it).

```sh
cd server
npm install
npm test                 # runs in Cloudflare's local runtime, no account needed
npm run typecheck

cp .dev.vars.example .dev.vars
npx wrangler d1 migrations apply soapstone --local
npm run dev              # http://localhost:8787
npm run smoke            # in another terminal: two fake companions, end to end
```

Schema changes go in a new numbered file in `migrations/`; never edit one
that's been applied.

## Deployed

Live at **https://soapstone-server.george-plendl.workers.dev** (George's
Cloudflare account; D1 database `soapstone`, region WNAM). Deployed
2026-10-06, and the smoke test passes against it.

- **Update the code:** `npm run deploy`.
- **Schema changes:** add a numbered file in `migrations/`, then
  `npm run db:migrate` (remote) before deploying code that needs it.
- **The secret:** `SERVER_SECRET` was set once with the first deploy (a
  random value that was never written down). Changing it with
  `npx wrangler secret put SERVER_SECRET` only invalidates sign-up
  puzzles in flight and hashed IP limits; tokens don't depend on it.
- **Check it:** `npm run smoke -- https://soapstone-server.george-plendl.workers.dev`
  (registers two test installs and leaves one test stone in region `us`).

How it was set up, for a fresh account: `npx wrangler login`;
`npx wrangler d1 create soapstone` and put its id in `wrangler.jsonc`;
`npm run db:migrate`; then deploy with a secrets file holding a long random
`SERVER_SECRET` (`npx wrangler deploy --secrets-file <file>`), and delete
the file.

## Not built yet

- The admin page (reported stones, bans, releasing names).
- Releasing names unused for six months, and pairing or recovery codes.
- Dropping impossible unlocks (many continents within a minute).
