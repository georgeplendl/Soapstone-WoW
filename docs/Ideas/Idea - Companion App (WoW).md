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
It also keeps track, for each character, of which stones they've unlocked,
so that progress lives on the server and not just in one SavedVariables
file. The hidden chat channel stays, but only for **live drops**: a stone
appears in seconds for players in the zone, straight from its author. The
database does everything else (see [The live channel](#the-live-channel)).

---

### Decisions (v1)

| | Decision |
|---|---|
| **Platform** | **Windows first.** Built so a macOS version is a second build of the same code, not a rewrite |
| **Accounts** | **None.** No sign-in, no email. The app registers itself anonymously on first run |
| **Who a user is** | The **full character name** (`Mad-Decent`), as the addon already uses. Stones, votes and unlocks are all stored by name |
| **Owning a name** | The first install to use a name owns it; only that install can write as it (see [Identity](#identity-the-character-name)) |
| **Unlocks** | Stored on the server **per character**. An alt hasn't been there, so it hasn't read the stone |
| **Sharing** | **Hybrid.** The companion and database carry everything and are the source of truth. The hidden channel carries only **live drops, edits and deletes, straight from their author**, to players in the zone. P2P zone sync is retired |
| **Drops without the companion** | **v1: kept, not uploaded by others.** The author's copy waits in `pending`; players who saw it live keep it for 7 days. Witness uploads may come later |
| **Removing stones on sync** | A stone is removed only when the server says so (tombstone or rejection), **never just because the server doesn't have it** |
| **Sealed text** | Lightly **scrambled** in the data file, so stones can't be read casually in Notepad |
| **More than one computer** | **Not in v1.** A character belongs to one computer; adding a second with a pairing code comes later |
| **Installing the addon** | **The companion installs and updates it.** Players install one thing |
| **Data into the game** | Stranger text reaches the game as **encoded data the addon decodes and checks, never as Lua code** |
| **Unlock privacy** | A character's unlocks are visible **only to the install that owns it**. Found counts are public totals |
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

### What a player does

1. **Install the companion.** One installer, no admin prompt, no sign-in.
   It finds WoW, installs the Soapstone addon, registers itself in the
   background and sits in the system tray, starting with Windows.
2. **Play.** A stone someone drops while you're both in the zone appears in
   seconds. Stones left while you were away are there when you log in.
   **Sync** in the addon (a quick reload) is a rarely needed catch-up.

No username, no password, no account. The rough edges that remain:

- **Catching up needs a reload or login.** Only live drops arrive mid-session.
- **"Windows protected your PC"** until the companion is code-signed. Fine
  for a private beta, needed before a public release.
- **Players without the companion** see live drops from players nearby,
  but not stones from players who are offline.
- **Mac players** wait for the second build.

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
way. Nothing outside the game can push data into a running addon; the only
live path is other players, over the hidden channel
([The live channel](#the-live-channel)).

To make catching up painless, the addon gets a **Sync** button that simply
calls `ReloadUI()`, and the companion refreshes its files every couple of
minutes so any reload picks up the latest.

**To test: the chat log as a faster way out.** WoW writes
`Logs\WoWChatLog.txt` while you play, not just at logout. If the addon can
get your drops into that log, the companion could watch it and upload within
seconds instead of at the next save. That would also save drops from a
crash (below). Unverified: check on WoW Forever which messages the log
records, and that addon output can appear in it.

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
- Installs the `Soapstone` addon into each install's `Interface\AddOns` and
  keeps it updated, so the addon and companion versions always match.
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
that install's `WTF\Config.wtf`. **On WoW Forever's beta** (build 70235)
`GetCurrentRegion()` returns 90 and `Config.wtf` says `portal "test"`, so the
addon records region `test`: beta stones stay apart from launch ones, with no
wipe needed. That build also gave Forever its own project,
`WOW_PROJECT_CAMELOT = 18`; game types are fixed labels (`forever`) so a
renumbering never splits a game's stones.

Each WoW install folder (`_retail_`, `_classic_`, `_classic_era_`,
WoW Forever's own) has its own SavedVariables and its own `SoapstoneData`,
so two game types on one PC never see each other's stones.

---

### Files on disk

Inside each install:

```
Interface\AddOns\SoapstoneData\
  SoapstoneData.toc     installed once by the companion
  Stones.lua            written stones, scores, unlocks, acks       (kept)
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

**Never write stranger text as Lua code.** WoW runs `Stones.lua` and
`Sketches.lua` as Lua when it loads them. If the companion wrote stone text
as Lua strings, one escaping bug, or a compromised server, could make a
message break out of its string and run as code in every player's game. So
the files contain only data the addon decodes itself:

```lua
SoapstoneData_Stones = {
  format    = 1,                 -- refused if the addon doesn't know it
  writtenAt = 1791234567,
  records   = {
    "c1RvbmUgcmVjb3JkIG9uZQ==",  -- one base64 blob per stone
    "c1RvbmUgcmVjb3JkIHR3bw==",
  },
}
```

- The companion writes only numbers and base64 strings, whose alphabet
  (`A–Z a–z 0–9 + / =`) can't close a Lua string. That's checked again
  just before writing.
- Each blob decodes to one record in a simple field format: a stone, a
  removal, an acknowledgement, a refusal or an unlock. The format is
  documented at the top of `Soapstone/Companion.lua`; the companion writes
  it in `companion/src-tauri/src/soapdata.rs`, and both sides test against
  the same file, `tests/fixtures/companion/Stones.lua`. The addon decodes
  it and runs it through the same validation as today
  (`Codec.DecodeStone` rules: lengths, characters, zone ids, coordinates)
  before using it. Anything that fails is skipped.
- So the worst a bad server or a bug can do is put wrong text on a stone,
  never run code.

**Writing files safely.** The companion writes each file to a temp name in
the same folder, then renames it into place, so the game never loads a
half-written file. If a file can't be read anyway, only the helper addon
fails: Soapstone keeps the stones it had and shows "Companion: data
unreadable".

**Scrambling sealed text.** A stone has to show the moment you reach it,
with no network in game, so its words must already be in `Stones.lua`. That
means anyone could open the file in Notepad and read every sealed stone,
which defeats "you have to be there". The companion stores each stone's text
and sketch id scrambled with a simple key (for example, XOR with a key built
from the stone id, then base64), and the addon unscrambles a stone only when
you're in reach. This stops casual peeking, not a determined player, and
that's enough. The other option, sending the words only after the server
hears you've unlocked a stone, would mean reloading at every stone before
you could read it.

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

#### A drop's path to the database

Only the **author's own companion** uploads a stone, from the author's
SavedVariables. The live channel reaches players online, never the database.

1. **You drop a stone.** The addon adds it to your stones and to `pending`,
   and sends it over the live channel to players in the zone.
2. **The game saves SavedVariables** on `/reload`, logout, exit or
   disconnect. Until then the stone exists only in game memory (and on the
   screens of players who got it live).
3. **The companion sees the file change**, waits for it to settle, reads
   `pending` (without running it) and uploads the stone.
4. **The server checks it** (name ownership, limits, word filter,
   validation), stores it, and answers with an acknowledgement or a
   rejection with a reason.
5. **The acknowledgement goes into `Stones.lua`.** On the next load the
   addon marks the stone uploaded and clears it from `pending`.
6. **Everyone else** gets it on their next login or reload.

So a stone reaches the database **at the author's next reload or logout**:
minutes, or hours after a long session. Players nearby don't wait, since
they got it live.

- **Companion closed:** the stone waits in `pending`, even for weeks, and
  uploads whenever the companion next runs.
- **Game crash:** WoW doesn't save SavedVariables on a crash, so drops since
  the last save are lost. That's true of every addon. Pressing **Sync**
  after a drop you care about protects it; the chat-log path, if it works,
  would remove the risk.
- **Rejected:** the addon shows why on the next load ("Your stone in Durotar
  wasn't shared: too many nearby"). The stone stays visible only to you, and
  live copies others received disappear on their next sync (the server
  sends them the rejection as a tombstone).
- **Other players never upload your stone,** even if they got it live. Only
  your install owns your name.

**Which zones:** every zone you've visited in that game type (the addon
already records visits in `SoapstoneDB.zones`), plus the zones next to them.
Nearest and highest-rated first. New zones join the list after you visit
them.

**Keeping it fast:** each request asks for changes since a cursor, per zone,
compressed. An up-to-date zone costs almost nothing. The first sync of a
busy zone is a few hundred KB at most.

#### What goes up

- New stones, edits and deletes. The addon keeps a `pending` list in
  SavedVariables (it replaces the `outbox` P2P zone sync used).
- Votes (`ratings[id][characterKey]` for your characters).
- Unlocks: when a stone opens, the addon records it as `heard` (as it does
  today) with the time and character, and adds it to `pending`.
- Reports (a new **Report** button on the stone window).

#### What comes down

- Stones and tombstones for your zones, and shared scores.
- Each stone's **found count** ("Found by 14 players"), for its author.
- Unlocks for the characters on this install, from every zone, so progress
  survives a reinstall or a wiped SavedVariables. The server keeps the
  earliest unlock time if both sides have one.
- Drawings for sketch stones in those zones (to `Sketches.lua`).
- Acknowledgements for your uploads.

---

### Identity: the character name

**A user is a character, named the way the addon already names them:**
`Mad-Decent` (on WoW Forever, first and last name; elsewhere, name and
realm). Within a game type and region it's unique, so stones, votes and
unlocks are all stored by that name. There's no separate account or player
id. Each character has its own unlocks, the way WoW keeps achievements and
explored zones per character.

**The name says who, but it can't prove it.** The server never talks to
Blizzard; it only sees a request saying "I'm Mad-Decent". The name comes
from a text file, so anyone could claim it. So each name gets a lock:

- On first run, the companion **registers an install**: it generates a
  random install id and a secret, solves a small proof-of-work puzzle (a
  second or two of CPU on one PC, expensive for a script registering
  thousands), and gets back a token. The player never sees it.
- The first install to upload anything as a character (a stone, vote or
  unlock) **owns that name** for that game type and region. It can only
  claim characters the addon has seen log in on that install (from
  `SoapstoneDB.meta`), which makes claiming someone else's name take a
  deliberate hand edit. After that,
  only that install can post, edit, delete, vote or record unlocks as
  `Mad-Decent`.

The name is the address; the token is the key.

**Stones are public; unlocks are private.** Anyone can download stones,
scores and found counts. A character's unlocks, with their times, show where
that character has been and when, so the server sends them only to the
install that owns the character.

#### v1: one computer per character

In v1 a character belongs to the one install that claimed it.

- **A second computer** (say, a Mac next to the PC) can still download
  everything for that character, unlocks included, but can't upload as it.
  Its drops, votes and unlocks stay in that machine's `pending` list, and
  the tray shows "Mad Decent is linked to another computer".
- **Reinstalling** keeps the token if the app's data folder
  (`%APPDATA%\Soapstone`) survives. If it's lost during the beta, the name
  is released by hand on the server.
- **Names that go quiet:** if an owned name hasn't been used for about six
  months, the server releases it, since a deleted character's name can be
  taken by someone else in game.

#### Later: adding computers and moving characters

- **Pairing code:** the first computer shows a short code ("7F3-K9Q"); typed
  into a second computer's companion, it lets that install own the same
  names too. Its waiting `pending` changes then upload.
- **Recovery code:** shown once at first run, it moves an install's names
  to a new install after a lost data folder, without asking anyone.
- **Renames and transfers:** a renamed character looks like a new one with
  no unlocks. A "move my progress from Old-Name" option can come later.
- **Real proof:** if WoW Forever ever offers Battle.net sign-in with a
  character list, as Retail does, that proves ownership outright and could
  replace the lock and codes.

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
- **Unlocks:** only from characters the install owns, and only for stones
  that exist. They're self-reported, so they're an honour system: fine for
  a character's own progress and found counts, not proof for anything
  competitive. The server can drop the impossible ones (dozens of unlocks
  across continents within a minute), and a character's own stones don't
  count toward their found count.
- **Reports:** a stone reported by 3 different installs is hidden until
  reviewed.
- **Shadow limits:** an install caught abusing keeps working from its own
  point of view, but its stones are only shown back to itself.
- **Word filter:** a short blocklist on upload, adjustable without an app
  update.

**Moderation needs a tool from day one:** a small private admin page to see
reported and hidden stones, restore or delete them, limit or ban an
install, and release a character name.

---

### Security and stability

What could go wrong, ranked by how much it matters.

| Risk | What could happen | How it's handled |
|---|---|---|
| **Code in stone text** | A message escapes its string in `Stones.lua` and runs as code in every player's game | Data goes in as base64 blobs the addon decodes and validates, never as Lua strings ([Files on disk](#files-on-disk)). Worst case is wrong text |
| **Update key stolen** | Whoever holds the companion's update-signing key can push a program to every player's PC | Tauri only installs updates signed with that key. Keep it offline and out of the repo, release from a protected GitHub Actions job, two-factor on the GitHub account |
| **Server compromised** | The attacker controls what stones everyone receives | Same as the first row: the addon treats every record as untrusted data, so the damage is limited to bad or missing stones |
| **Name squatting** | Someone hand-edits a file and claims `Mad-Decent` before the real player installs, then posts as them | Claims only for characters the addon has seen log in; admin can release a name and remove its stones. Can't be fully prevented without Blizzard's proof (Battle.net sign-in). It can't touch anyone's account or PC |
| **Spam and floods** | Thousands of junk stones or fake votes | Proof-of-work, rate limits, density caps, reports, word filter, shadow limits ([above](#stopping-mass-submissions-and-abuse)) |
| **Unlock privacy** | Someone tracks where a player has been and when | Unlocks go only to the owning install; others see totals |
| **Stolen token** | Malware on a player's PC posts as their characters | Low value; the token stays in the user's app data folder. Admin can reset it |
| **Blizzard's rules** | A companion that touches addon files is against the rules on Forever | Same file-only approach as WeakAuras Companion and the Raider.IO client. Confirm for Forever before release (open questions) |
| **Where a player has been** (accepted risk) | A stone carries its author's name, exact spot and drop time, so on a PvP realm someone could watch for fresh stones by a player and hunt them | Not handled for now (decided 2026-10-06). Later options: hold new stones back from others for a while, or show rough times only. Listed in SECURITY.md |
| **Request budget** | Floods use up the server plan's daily requests, even when refused | Per-minute limits per IP and per install, and a quieter companion; a firewall rule on a custom domain, or a paid plan, for the rest (SECURITY.md) |

**Stability:**

- **Half-written files:** the companion writes to a temp file and renames it;
  it reads SavedVariables only after the file has stopped changing.
- **A broken data file** only breaks the helper addon. Soapstone keeps its
  last good stones and says "Companion: data unreadable".
- **Server down or no internet:** the addon plays from its cache, and every
  drop, vote and unlock waits in `pending`. Nothing is lost.
- **Mismatched versions:** both data files carry a `format` number; an
  unknown one is refused with "Update the Soapstone companion". Since the
  companion installs the addon, they rarely drift apart.
- **Integrity of stones:** the server is the source of truth. Only a name's
  owner can edit or delete its stones, every change carries a version, and
  deletes leave a tombstone, so changes merge cleanly. Editing your own
  SavedVariables only fools your own game: anything uploaded still has to
  pass ownership and validation.

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
           score, found_count, updated_seq
sketches   id, w, h, data, created_at                             -- data = packed string
votes      stone_id, char_key, value, install_id, updated_at
unlocks    flavor, region, char_key, stone_id, unlocked_at,
           install_id, updated_seq                                -- one row per character per stone
reports    stone_id, install_id, reason, created_at
```

- **Partitioning:** every query filters on `(flavor, region, zone)`, with an
  index on `(flavor, region, zone, updated_seq)` for "changes since".
  Nothing is split by realm.
- **Stone ids** stay as the addon makes them today:
  `<CharacterKey>-<unix time>-<n>`. They're unique without coordination and
  the server checks the author part matches `author_key`.
- **`score`** is kept up to date on each vote, and **`found_count`** on each
  first unlock, so downloads don't have to count votes or unlocks.
- **`unlocks`** is keyed on `(flavor, region, char_key, stone_id)`, with an
  index on `(flavor, region, char_key, updated_seq)` so a companion can ask
  for "this character's unlocks since". Pushing an unlock that already
  exists keeps the earlier `unlocked_at`.
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
POST /v1/push                     stones, deletes, votes, unlocks, reports  → acks, rejections
GET  /v1/pull?flavor&region&zones&chars&since
                                  stones, tombstones, scores, found counts,
                                  sketch ids, unlocks for `chars`
POST /v1/sketches                 list of sketch ids → packed drawings
```

Later, with pairing and recovery codes:

```
POST /v1/pair                     pairing code → this install also owns those names
POST /v1/characters/move          recovery code → move ownership
```

Every endpoint is versioned (`/v1/`) so old companions keep working after
changes.

---

### The live channel

The P2P network did two jobs: **live drops** and **zone sync** (players
swapping whole zones of stones). Zone sync was the heavy part and what ran
into the ~1 message per second limit. The database now does that job, so
zone sync and the `outbox` are removed (`Sync.lua`). The hidden channel
stays for live drops only, which is a few messages per drop. `Net.lua` and
the codec's wire format are trimmed, not rewritten.

| | Live channel | Companion + database |
|---|---|---|
| Carries | **New drops, edits and deletes**, sent once by the author to players in the zone | **Everything:** stones, votes, unlocks, found counts, drawings |
| Reaches | Players online in that zone right now | Everyone, on login or reload |
| Role | Instant, but only for who's online | The source of truth; fills every gap |

**Trust: accept live stones only straight from their author.** WoW tells
the addon who sent each addon message, and that can't be faked, so a drop
from `Mad-Decent` really came from Mad Decent's client. A relayed copy of
someone else's stone proves nothing, so there's no relaying.

- Live stones carry the same id and version as in the database, so when the
  next download includes them they merge without duplicates.
- They go through the same validation as everything else, and the addon's
  own limits (one drop per 30 s, 140 characters) apply on both ends.
- If the server rejects one (rate limit, word filter, banned install), the
  rejection comes down as a tombstone and the live copies disappear.
- **Text only.** Drawings are companion-only, so a sketch stone arrives live
  as a pin and "sketch by …", and the drawing comes with the next sync.
- Votes and unlocks never go over the channel; they're personal and go
  through the companion.

[[Idea - Network Resilience (WoW)]] applies again, in a smaller form: backup
channels and the additive wire format still matter for live drops; coalesced
replies and the census mattered mostly for zone sync.

#### Drops from players without the companion

A player without the companion can still drop a stone; it goes out live to
players in the zone and waits in their own `pending`. It doesn't reach the
database, because only the author's own install uploads stones.

**v1: keep it, don't upload it for them.**
- The author's copy uploads if they install the companion, however much
  later.
- Players who got it live keep it locally for **7 days**, marked as not yet
  in the database, then drop it if the database still hasn't heard of it.
- This needs the rule from the decisions: **a sync removes a stone only when
  the server says so**, never just because the server doesn't have it.
  Otherwise live-only stones would vanish on everyone's next sync.

**Later, if the beta shows many drops without the companion: witness
uploads.** Players with the companion who received the stone live upload it
on the author's behalf. The server can't see the channel, so it has to take
witnesses at their word, and a dishonest one could invent stones. Safeguards:
- accept a stone only once **2–3 different installs** report it identically
  (same id, text and spot);
- only for names **no install owns**; an owned name's own install uploads;
- mark it **witnessed** with tighter limits. If the author installs the
  companion later, they claim the name and its stones.

**Ruled out: requiring the companion to drop.** Cleanest for integrity, but
it turns away players who'd leave one stone before deciding to install
anything.

---

### The Windows app

- **Framework: Tauri.** Rust core, system webview for the small UI window.
  Around 10 MB. The same code builds for macOS later.
- **Tray icon** with: detected installs (game type, region, account), last
  sync, drops waiting to upload, "Start with Windows" (on by default), open
  logs, quit.
- **Install:** per-user installer (NSIS), no admin prompt. "Start with
  Windows" uses the per-user startup registry key.
- **Managing the addon:** the companion carries the matching `Soapstone`
  addon and copies it into each install's `Interface\AddOns`, replacing an
  older copy (never touching SavedVariables). It skips a folder that's a
  link to a git checkout, so a developer's working copy isn't overwritten.
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
   upload list (drops, votes, unlocks with their time and character),
   loading `SoapstoneData` with validation and unscrambling, the
   "Companion:" status line, the Sync (reload) button, drop cooldown and
   per-zone cap.
2. **Server:** register, push, pull (including unlocks and found counts),
   sketches, name ownership, with the rate limits and validation from day
   one, and the admin page. Test it with a script before any app exists.
3. **Companion core (Windows):** find installs, install the addon, parse
   SavedVariables, push and pull, write `Stones.lua` (encoded and scrambled)
   and `Sketches.lua` safely. A plain tray app, unsigned, for a private
   beta.
4. **Trim P2P to the live channel:** remove zone sync and the `outbox` once
   the companion carries stones; keep author-only live drops, add the
   7-day keep for stones not yet in the database and the "remove only on
   the server's word" rule. Test the chat-log path on Forever.
5. **Private beta** with a handful of players on WoW Forever. Tune limits.
6. **Reports, word filter, shared scores and found counts in the addon**,
   then [[Idea - Zone Leaderboard (WoW)]].
7. **Signing, auto-update, public release.** Pairing and recovery codes,
   then macOS.

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
- What region ids does WoW Forever report at launch? (Beta: 90, recorded as `test`.)
- Does WoW Forever offer Battle.net sign-in with a character list? If so,
  it could prove who owns a name and replace the install lock.
- Should a stone that's been read stay readable from anywhere? Today it
  doesn't (you go back to it), but the first unlock prints the full text to
  chat, so it can be scrolled back to. Decide whether chat shows the words
  or just a hint.
- Classic has several kinds of realm (Era, Hardcore, Season of Discovery,
  Anniversary, progression). Pool them all under one game type, or keep
  some apart because their worlds differ?
- Does WoW Forever write `Logs\WoWChatLog.txt` during play, and can the
  addon's output reach it? If so, drops can upload within seconds.
- How many drops come from players without the companion? Decides whether
  witness uploads are worth building.
- The exact limits (drops per day, stones per spot) are guesses until the
  private beta.

---

### Related

- `docs/Sharing - Architecture.md`: the P2P network, message budget,
  identity, zone keys.
- [[Idea - Zone Leaderboard (WoW)]]: needs shared, trustworthy votes.
- [Idea - First Discovery Bonus](https://github.com/georgeplendl/Soapstone/blob/main/docs/Ideas/Idea%20-%20First%20Discovery%20Bonus.md) (phone app): needs a server to know who read a stone
  first.
