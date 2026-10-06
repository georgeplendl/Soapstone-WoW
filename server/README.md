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

- **Names:** the first install to write as a character (`Mad-Decent`) owns
  it; nobody else can post, edit, delete, vote or unlock as it.
- **Validation:** the addon's own rules (`Soapstone/Codec.lua`): ids belong
  to their author, text 1–140 letters, sketches 160×60 that decode cleanly,
  sane positions.
- **Limits per day:** 30 new stones per install and 10 per character, 60
  edits, 200 votes, 2,000 unlocks, 20 reports, 5 new installs per IP.
- **Density:** 10 live stones per character per zone; 3 stones within 10
  yards of each other.
- **Word filter** (`blocked_words` table) and duplicate text within a day.
- **Reports:** 3 installs reporting a stone hide it.
- **Shadow limits:** a `limited` install's stones are shown only to itself.
- **Unlocks are private:** only the owning install downloads them; others see
  a stone's found count.

Limits can be changed with the `LIMIT_*` settings in [`src/env.ts`](src/env.ts).

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
