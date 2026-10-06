#idea, #soapstone, #wow, #sharing, #companion

> **WoW-specific.** This idea is for the Soapstone-WoW addon: a small desktop
> app that sits beside World of Warcraft and connects the addon to a shared
> database. It doesn't apply to the phone app.

## Companion App: A Database Behind the Stones

Today every stone lives on players' machines and travels player to player
(`docs/Sharing - Architecture.md`). That needs nothing but the addon, but:

- **Stones only exist while someone online holds them.** Early on, a zone
  looks empty unless its authors happen to be logged in.
- **Ratings can't add up.** A stone's score is only what your client has
  seen (see [[Idea - Zone Leaderboard (WoW)]]).
- **Bandwidth.** About 1 addon message per second per sender, so a first
  visit to a busy zone takes a minute or more.

The companion is a small Windows app that runs next to the game. It uploads
the stones you leave and brings back everyone else's from a shared database.

---

### Decisions (v1)

| | Decision |
|---|---|
| **Platform** | **Windows first.** Built so a macOS version is a second build of the same code, not a rewrite |
| **Accounts** | **None.** No sign-in, no email. The app registers itself anonymously on first run |
| **Game types** | Detected automatically. Forever, Classic and Retail stones **never mix** |
| **Realms** | **Ignored.** Stones are shared across every realm of a game type, so the world doesn't feel empty |
| **Region** | Stones are split by **WoW region** (US, EU, KR, TW). Players can't message across regions anyway, and it keeps each sync small and fast |
| **Offline drops** | The addon always records your drops. They upload the next time the companion runs |
| **Local cache** | The last-synced **written** stones stay on disk and show up even when the companion is closed |
| **Drawings** | Only shown while the companion is running. They're never kept in the long-lived cache |
| **Abuse** | Limits in the addon for honest players, and hard limits on the server for everyone else |

"Region" here means the WoW region your account plays in, not the map
region. Within a region, the companion still fetches stones zone by zone
(below).

---

### The hard constraint: addons can't talk to the outside world

WoW addons have no network or file access. The only file an addon writes is
its **SavedVariables**. The only files it reads are ones that were there
when it loaded.

| Direction | How | When |
|---|---|---|
| **Game → companion** | The companion watches `WTF\Account\<ACCOUNT>\SavedVariables\Soapstone.lua` | WoW writes it on **logout, `/reload` and disconnect**, not during play |
| **Companion → game** | The companion writes files in a helper addon, `Interface\AddOns\SoapstoneData\` | The game reads them on **login and `/reload`** |

So the companion **isn't live**. Your drops reach the database when you
reload or log out, and other players' stones reach you on your next login or
reload. WeakAuras Companion and TradeSkillMaster's desktop app work the same
way.

To make this painless, the addon gets a **Sync** button that simply calls
`ReloadUI()`, and the companion refreshes its files every couple of minutes
so any reload picks up the latest.

**Ruled out:** reading pixels off the screen, sending keystrokes into the
game, or reading game memory. That's how bots work, and it would put
players' accounts at risk.

---

### Working together: who does what

**The addon** (source of truth for what's happening in game):
- Detects the game type and region and writes them into SavedVariables, so
  the companion never has to guess from folder names.
- Records every drop, edit, delete and vote in SavedVariables, whether or
  not the companion is running. Nothing is lost if the companion is closed
  for a week.
- Loads the companion's files on login, checks every record before
  accepting it, and shows "Companion: synced 2 min ago" or "Companion: not
  running (last synced 3 days ago)".
- Keeps its own gentle limits (drop cooldown, stones per zone) so honest
  players never hit the server's.

**The companion** (the only thing that talks to the internet):
- Finds WoW installs and their SavedVariables.
- Uploads pending changes, downloads stones for your game type and region,
  writes the helper addon's files.
- Sits in the system tray. No window unless you open it.

#### Detecting the game type and region

The addon already works out the game type (`Identity.Flavor()`: `forever`,
`retail`, `classic`, `classic-<id>`). It adds the region:

```lua
SoapstoneDB.meta = {
  flavor = "forever",        -- Identity.Flavor()
  region = "us",             -- from GetCurrentRegion(): 1 us, 2 kr, 3 eu, 4 tw, 5 cn
  build  = "1.60.1.70009",
  addon  = "0.5.0",
}
```

The companion reads `meta` from each install's SavedVariables and keeps a
separate cache for each (game type, region) pair. If `GetCurrentRegion`
doesn't exist on a client, the companion falls back to the `portal` line in
that install's `WTF\Config.wtf`. **To verify on WoW Forever:** that
`GetCurrentRegion()` exists and returns a sensible value.

Each WoW install folder (`_retail_`, `_classic_`, `_classic_era_`,
WoW Forever's own) has its own SavedVariables and its own `SoapstoneData`,
so two game types on one PC never see each other's stones.

---

### Files on disk

Inside each install:

```
Interface\AddOns\SoapstoneData\
  SoapstoneData.toc     installed once by the companion
  Stones.lua            written stones, scores, acknowledgements   (kept)
  Sketches.lua          drawings                                    (companion running only)
```

**Why a separate addon** instead of writing into `Soapstone.lua` or the
`Soapstone` folder: WoW overwrites SavedVariables on logout, and addon
updates replace the `Soapstone` folder. WoW only discovers **new** files
when the client starts but re-reads **changed** files on `/reload`, so the
companion creates both files once (empty if need be) and then only rewrites
them.

**`Stones.lua`: the local cache.** Written stones, tombstones, shared scores,
and acknowledgements of your uploads. It stays on disk when the companion
closes, so the last-synced stones still show up the next time you play
without it. Capped like today: newest 200 others' stones per zone, about
5,000 in total, so it stays around 1–2 MB.

**`Sketches.lua`: drawings, only while the companion runs.** The companion
writes it with a `writtenAt` time and refreshes it every few minutes. When
the companion closes normally, it empties the file. If it crashes, the addon
ignores a `Sketches.lua` older than about 15 minutes (the addon and the
companion share the same PC clock). Sketch stones still appear on the
minimap from `Stones.lua`; opening one without the companion says "Start
the Soapstone companion to see this drawing." Your **own** drawings always
show, since they're in your SavedVariables.

**Writing Lua safely.** Stone text is typed by strangers. The companion must
write every string with full Lua escaping (quotes, backslashes, newlines,
`]]`) so a message can never break out of its string and run as code in
other players' games. The addon still runs every record through the same
validation as zone sync (`Codec.DecodeStone` rules) before using it.

---

### Sync loop

1. **Start:** the companion reads each install's SavedVariables, uploads
   anything pending, then downloads changes since its last sync.
2. **While running:** it watches SavedVariables for changes (each reload or
   logout) and uploads right away. It asks the server for changes every
   ~2 minutes and rewrites `Stones.lua` and `Sketches.lua`.
3. **Acknowledgements:** uploaded ids go into `Stones.lua` as `acks`. On the
   next load, the addon marks those stones as uploaded, so nothing is sent
   twice.
4. **Exit:** it empties `Sketches.lua`.

**Which zones:** every zone you've visited in that game type (the addon
already records visits in `SoapstoneDB.zones`), plus the zones next to them.
Nearest and highest-rated first. New zones join the list after you visit
them.

**Keeping it fast:** each request asks for changes since a cursor, per zone,
compressed. An up-to-date zone costs almost nothing. The first sync of a
busy zone is a few hundred KB at most.

#### What goes up

- New stones, edits and deletes. The addon keeps a `pending` list in
  SavedVariables (next to the existing `outbox`, which the P2P network
  uses).
- Votes (`ratings[id][characterKey]` for your characters).
- Reports (a new **Report** button on the stone window).

#### What comes down

- Stones and tombstones for your zones, and shared scores.
- Drawings for sketch stones in those zones (to `Sketches.lua`).
- Acknowledgements for your uploads.

---

### Identity without sign-in

On first run, the companion **registers an install**: it generates a random
install id and a secret, solves a small proof-of-work puzzle (a second or
two of CPU on one PC, expensive for a script registering thousands), and
gets back a token. All uploads use that token.

**Owning a character name:** the first install to upload a stone by a
character (say `Mad-Decent`) owns that name for that game type and region.
After that, only that install can post, edit or delete as `Mad-Decent`.
It's not proof, but it stops anyone else from impersonating an existing
author or editing their stones. A player who reinstalls gets a "Move my
characters to this install" option using a recovery code shown at first
run.

---

### Stopping mass submissions and abuse

SavedVariables is a plain text file, so anyone can hand-edit it or write a
script that pretends to be the companion. **The server is the real gate.**
The addon's and companion's limits are there so honest players never hit
the server's.

| Layer | Limits |
|---|---|
| **Addon** | 1 drop per 30 s; at most 10 live stones per character per zone; text ≤ 140 characters; sketch format checked; one vote per stone per character |
| **Companion** | Re-checks everything before upload; never sends more than the server allows; backs off when told to |
| **Server** | Everything below, whatever the client claims |

Server rules:
- **Registration:** proof-of-work, plus a cap on new installs per IP per day.
- **Rate limits:** per install and per IP. For example: 30 new stones per day
  per install, 10 per character, 200 votes per day per install. Requests
  over the limit get `429` and the companion waits.
- **Density:** at most 10 live stones per character per zone, and at most N
  stones from anyone within ~10 yards of each other, so no one can carpet a
  spot.
- **Validation:** same rules as the addon (text length and characters,
  sketch size and alphabet, known zone ids, sane coordinates). Duplicate
  text from the same install within a day is refused.
- **Votes:** one per character per stone, only from characters the install
  owns. An install can't vote on its own characters' stones.
- **Reports:** a stone reported by 3 different installs is hidden until
  reviewed.
- **Shadow limits:** an install caught abusing keeps working from its own
  point of view, but its stones are only shown back to itself.
- **Word filter:** a short blocklist on upload, adjustable without an app
  update.

---

### The database

**Recommended: Cloudflare Workers with D1 (SQLite).** One small API,
serverless, fast from anywhere, and free or a few dollars a month at this
size. Postgres (Supabase, Neon) would work just as well and can replace it
later if needed.

**Tables:**

```
installs   id, secret_hash, created_at, ip_hash, status (ok | limited | banned)
characters flavor, region, char_key, install_id                  -- who owns a name
stones     id, flavor, region, zone, instance, wx, wy, map_id, x, y,
           author, author_key, kind (text | sketch), text, sketch_id,
           v, t, edited_at, deleted_at, install_id, status (live | hidden),
           score, updated_seq
sketches   id, w, h, data, created_at                             -- data = packed string
votes      stone_id, char_key, value, install_id, updated_at
reports    stone_id, install_id, reason, created_at
```

- **Partitioning:** every query filters on `(flavor, region, zone)`, with an
  index on `(flavor, region, zone, updated_seq)` for "changes since".
  Nothing is split by realm.
- **Stone ids** stay as the addon makes them today:
  `<CharacterKey>-<unix time>-<n>`. They're unique without coordination and
  the server checks the author part matches `author_key`.
- **`score`** is kept up to date on each vote, so downloads don't have to
  count votes.
- **`updated_seq`** is a counter bumped on every change. The companion's
  cursor is just the highest one it has seen.

**Drawings: stored and named by content.** A sketch is the addon's existing
packed string (160×60, base-32 varints in a base64 alphabet, a few hundred
characters). It's small enough to live directly in the database:

- **Name:** `sk_` + the first 16 hex characters of the SHA-256 of the packed
  string, e.g. `sk_9f2c41e07ab35d18`. The same drawing always gets the same
  name, so duplicates are stored once and a spam drawing can be blocked by
  name.
- **Never changed in place.** Editing a drawing makes a new sketch; the
  stone points at the new name and its version goes up.
- The stone record carries `sketch_id`, so `Stones.lua` can show the pin and
  "sketch by Osha Compliant" without the drawing itself.
- If drawings ever grow (colour, bigger canvas), move them to object storage
  (Cloudflare R2) under the same names, `sketches/sk_9f2c41e07ab35d18.bin`.
  Nothing else has to change.

**API:**

```
POST /v1/register                 proof-of-work → install id + token
POST /v1/push                     stones, deletes, votes, reports  → acks, rejections
GET  /v1/pull?flavor&region&zones&since   stones, tombstones, scores, sketch ids
POST /v1/sketches                 list of sketch ids → packed drawings
POST /v1/characters/move          recovery code → move ownership
```

Every endpoint is versioned (`/v1/`) so old companions keep working after
changes.

---

### The P2P network

The P2P network is already built. With a database behind the stones, it's
no longer the main way to share. Options:

1. **Keep it for live drops only** *(recommended)*: a stone dropped near you
   appears right away through the channel, without waiting for a reload.
   Drop P2P zone sync, since the database does that job.
2. Keep all of it, as a fallback for players without the companion.
3. Remove it and rely on the companion entirely. Simplest, but players
   without it see nothing new.

If drawings are to be companion-only, P2P should carry text stones only.

---

### The Windows app

- **Framework: Tauri.** Rust core, system webview for the small UI window.
  Around 10 MB. The same code builds for macOS later.
- **Tray icon** with: detected installs (game type, region, account), last
  sync, drops waiting to upload, "Start with Windows" (on by default), open
  logs, quit.
- **Install:** per-user installer (NSIS), no admin prompt. "Start with
  Windows" uses the per-user startup registry key.
- **Finding WoW:** Blizzard's install-path registry key, then Battle.net's
  `C:\ProgramData\Battle.net\Agent\product.db`, then common locations on
  every drive (`D:\Games\World of Warcraft\`), then "Choose folder…".
  Inside, each game-type folder (`_retail_`, `_classic_`, `_classic_era_`,
  WoW Forever's folder) and each `WTF\Account\<ACCOUNT>`.
- **Reading SavedVariables:** a small parser for Lua table literals. It
  never runs the file. It waits for the file to stop changing (WoW writes it
  in one go at logout) before reading.
- **Updates:** Tauri's updater checks the latest GitHub release.
- **Signing:** a Windows code-signing certificate (Azure Trusted Signing is
  about $10 a month; check it's available to individuals in your country).
  Without one, Windows SmartScreen shows "Windows protected your PC".
  Unsigned builds are fine for a private beta.
- **Distribution:** GitHub Releases next to the addon zip, from the same
  release process (`tools/release.py`). `Soapstone-Companion-vX.Y.Z-setup.exe`.
  A GitHub Actions job on a Windows runner builds and signs it.

#### Later: macOS

Kept in mind from the start:
- All file paths go through one "find WoW installs" module with a Windows
  and a macOS implementation (`/Applications/World of Warcraft/`,
  `/Users/Shared/Battle.net/Agent/product.db`).
- No Windows-only APIs outside that module and the startup setting.
- macOS needs the Apple Developer Program ($99 a year) and notarization,
  a universal build (Apple Silicon and Intel), and a login item instead of
  the startup registry key.

---

### Build order

1. **Addon groundwork:** `meta` (game type, region, build), a `pending`
   upload list, loading `SoapstoneData` with validation, the "Companion:"
   status line, the Sync (reload) button, drop cooldown and per-zone cap.
2. **Server:** register, push, pull, sketches, with the rate limits and
   validation from day one. Test it with a script before any app exists.
3. **Companion core (Windows):** find installs, parse SavedVariables, push
   and pull, write `Stones.lua` and `Sketches.lua` safely. A plain tray app,
   unsigned, for a private beta.
4. **Private beta** with a handful of players on WoW Forever. Tune limits.
5. **Reports, word filter, shared scores in the addon**, then
   [[Idea - Zone Leaderboard (WoW)]].
6. **Signing, auto-update, public release.** macOS after that.

---

### Costs at a glance

| Item | Rough cost |
|---|---|
| Cloudflare Workers + D1 | Free to ~$5 / month at first |
| Windows code signing | ~$10 / month (Azure Trusted Signing) or a few hundred $ / year |
| Apple Developer Program (later, for macOS) | $99 / year |

---

### Open questions

- Does WoW Forever allow companion apps reading and writing addon files, as
  Retail and Classic do? Check Blizzard's policy for that client.
- Does `GetCurrentRegion()` exist on WoW Forever?
- P2P: keep for live drops only (recommended), keep all, or remove?
- Classic has several kinds of realm (Era, Hardcore, Season of Discovery,
  Anniversary, progression). Pool them all under one game type, or keep
  some apart because their worlds differ?
- The exact limits (drops per day, stones per spot) are guesses until the
  private beta.

---

### Related

- `docs/Sharing - Architecture.md`: the P2P network, message budget,
  identity, zone keys.
- [[Idea - Zone Leaderboard (WoW)]]: needs shared, trustworthy votes.
- [Idea - First Discovery Bonus](https://github.com/georgeplendl/Soapstone/blob/main/docs/Ideas/Idea%20-%20First%20Discovery%20Bonus.md) (phone app): needs a server to know who read a stone
  first.
