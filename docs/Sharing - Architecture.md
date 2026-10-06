# Sharing — Architecture

How Soapstone stones get from the player who drops them to every other player
who walks past, with nothing to install but the addon.

**Status (2026-10-06): superseded for sharing.** Stones are now shared
through the companion app and its server
([Idea - Companion App (WoW)](Ideas/Idea%20-%20Companion%20App%20(WoW).md)),
so the "no server" constraint below no longer holds. The network described
here still exists but has been **off by default since 0.3.1** (`/soap net
join`). The plan is to trim it to live drops from a stone's own author and
remove zone sync. This page is kept as the record of how it works and what
was learned on the WoW Forever client.

*Earlier status (2026-09-25):* steps 1–3 built. Zone sync works on the
simulated network in `tests/`; it hasn't yet run between two real players.

---

## Constraints

| Constraint | Consequence |
|---|---|
| Players install **only the addon**: no companion app, no login | There is **no central server or database**. WoW addons cannot make network requests, and without a companion app nothing outside the game can reach them. |
| Addons *can* send hidden **addon messages** to other players running the same addon | Stones travel **player to player**. The "database" is the network of Soapstone players, each keeping a local copy. |
| Target **WoW Forever** now; support Retail and Classic later as **separate databases** | Every stone and message carries a *flavour* key. |
| **Sync by zone**, not the whole world | Entering a zone fetches that zone's stones; the local cache is capped per zone. |
| Identity is the **character name**, no login | The sender name WoW attaches to every addon message *is* the identity. |
| **No moderation** for now | Abuse limits live in code: size caps, per-author caps, flood ignoring. |

---

## What we learned from the WoW Forever client

| Question | Answer (2026-09-25) |
|---|---|
| `WOW_PROJECT_ID` | `1`, the mainline/retail codebase, even though the build is 1.60.1 |
| Interface number | `16001` |
| `UnitName` / `UnitFullName("player")` | `"Mad", "Decent"`: the second name sits in the **realm** slot |
| `GetUnitName("player", true)` | `"Mad Decent"`: the UI joins the two with a space |

### Solo self-test results (2026-09-25, character "Osha Compliant")

| # | Result | Consequence |
|---|---|---|
| T1 | Hidden channel joined (`/6`), invisible in chat; messages round-trip | The transport works on WoW Forever |
| T3 | Sender arrives as **`"Osha Compliant"`**, with a space, on both channel and whisper | `KeyFromSender` already folds it to `Osha-Compliant` |
| T5 | Whisper to `Osha-Compliant` ✅, `"Osha Compliant"` ✅, `Osha` ❌, and the failure shows a **visible** system message: "No player named 'Osha' is currently playing." | Always whisper the full key. Before step 3, filter that system message for players we contact by addon message, since peers go offline mid-sync |
| T6 | `SAY` and `YELL` → `InvalidChatType` outside instances; guild untested | The channel plus whispers is the transport; party and guild are extras |
| — | **~675 ms round trip** on channel and whisper alike | Timeouts and answer-suppression windows must allow > 1 s; prefer few, larger messages |
| T4 | 30 at once: **9 ok**, 1 `ChannelThrottle`, 20 `AddonMessageThrottle`; **9 of 30 returned** | A burst allowance of about **9–10 messages per prefix** |
| T4b | Pace test, 4/s for 20.3 s after spending the burst: **21 `ChannelThrottle`, 59 `AddonMessageThrottle`, 20 returned** | **Sustained ≈ 1 message/s.** `ChannelThrottle` = queued and **delivered late** (20 of 21 came back; the last was likely still in flight). `AddonMessageThrottle` = **dropped** |

### Message budget

Per sender, per prefix: **~10 messages in a burst, then ~1 per second**, each
≤ 255 bytes. So roughly **250 bytes/s per sender**, shared by everything
Soapstone sends. Design rules that follow:

- **Never send into `AddonMessageThrottle`.** Keep our own token bucket
  (10, +1/s) and queue locally; treat `ChannelThrottle` as sent.
- **Only send what's missing.** An up-to-date zone costs one digest
  exchange. A first visit is where the cost lands: e.g. 30 text stones
  (~1 message each) plus 10 sketches (~3 each) ≈ 60 messages ≈ 1 minute
  from one peer.
- **Nearest first.** Transfer stones closest to the player first, and text
  before sketches.
- **Sketch pixels on demand.** Sync a sketch's *pin* (id, position,
  author, size) with the zone, but fetch its pixels only when the player
  comes within the "somewhere close" range. Most sketches are never opened.
- **Spread the load across peers.** The limit is per sender, so asking
  several peers for different stones multiplies throughput.
- **Keep broadcasts rare and tiny.** They spend the same budget and reach
  everyone on the channel.
- **Compression** (LibDeflate) before splitting into messages, for anything
  over one message.

---

## Flavour: keeping the games apart

WoW Forever, Retail and Classic have different maps, zones and IDs, so their
stones must never mix.

| Client | `WOW_PROJECT_ID` | Build | Flavour key |
|---|---|---|---|
| WoW Forever | 1 | 1.x | `forever` |
| Retail | 1 | 11.x / 12.x | `retail` |
| Classic Era | 2 | 1.15.x | `classic` |
| Other Classic | 3+ | varies | `classic-<id>` |

Players on different games can't message each other anyway, and each client
keeps its own saved data. The key is still written on every stone and every
message (`Identity.Flavor()`), so nothing can cross by accident.

---

## Identity

- **Key:** WoW's standard `Name-Realm` form built from `UnitFullName`:
  **`Mad-Decent`**. Unique, because WoW Forever names are unique.
- **Display:** "Mad Decent" on WoW Forever, matching the game's own UI.
  On realm servers the second part really is a realm, so keep `Mad-Stormrage`.
- **Incoming messages:** `CHAT_MSG_ADDON` gives a `sender` string that
  **the server sets, so a sender can't fake it**. It may arrive as
  `Mad-Decent`, `Mad Decent` or `Mad`; `Identity.KeyFromSender` folds all
  three into the key. **WoW Forever sends `"Mad Decent"`** (with a space;
  self-test T3).
- **Stone IDs:** `Mad-Decent-<unix time>-<n>`, unique across all players with
  no coordination.
- **First-hand vs relayed:** a stone received *from its author* has a
  verified author. A stone passed along by someone else could have a forged
  author field, so we record who relayed it (`via`). The stone upgrades to
  verified when the author's own client later confirms it.

---

## Transport

- **Prefix:** `Soapstone` (registered with `C_ChatInfo.RegisterAddonMessagePrefix`).
- **Channel:** a custom channel, **`SoapstoneNet`**, joined automatically a
  few seconds after login so General and Trade keep their usual numbers, and
  removed from every chat window so players never see it.
- **Broadcasts** (small announcements) go to the channel; **bulk transfers**
  go by `WHISPER` addon messages directly between two players.
- **Wire format:** `S1;<flavour>;<TYPE>;<fields…>`. `S1` is the protocol
  version; anything with another version or flavour is ignored.
- **Size and rate:** a message is at most 255 bytes, and the client throttles
  per prefix: about 10 at once, then about 1 per second (tests T4/T4b; see
  *Message budget*). Larger payloads (sketches: ~350–900 chars) are split into
  parts and paced. We'll likely embed the standard libraries (ChatThrottleLib,
  AceComm, LibSerialize, LibDeflate) inside the addon folder, so players still
  install a single folder.

---

## Zone sync (step 3, built: `Sync.lua`, `Codec.lua`)

The **zone key** is the zone-level map ID. From `C_Map.GetBestMapForUnit`,
climb parents until the map type is *Zone*; Thunder Bluff is `1456`.

After you've been in a zone for 4 seconds (so passing through doesn't
count), or once the network channel is joined after login:

```
you  ─channel─►  ZQ zone digest count          "who has this zone?"
peer ─channel─►  ZH zone digest count          offer, after a random 0.4–2.5 s;
                                               anyone about to offer the same
                                               digest hears it and stays quiet
you  ─whisper─►  ZL zone <16 bucket fingerprints>     to the biggest offer
peer ─whisper─►  [ZI] zone,id:v,id:v…          entries in buckets that differ
you  ─whisper─►  [ZG] zone,id,id…              the ones you lack or have older
peer ─whisper─►  [ST] <stone> …  ZE zone n     text and deletions first, then sketches
peer ─whisper─►  ZX zone reason                can't help right now (busy)
```

`[..]` are multi-part payloads (up to 200 bytes per message, reassembled on
arrival). Stone records are 16 `~`-separated fields with `%XX` escaping
(see `Codec.lua`); a sketch record is ~450 characters, so 3 messages.

- **Fingerprints:** a zone's shareable stones and tombstones are split into
  16 buckets by id. Each bucket's fingerprint is an order-independent sum
  of `hash("id:v")`; the zone digest is a hash of all 16. An up-to-date zone
  costs **one broadcast**, and a partial difference only lists the buckets
  that differ.
- **Suppression:** random backoff, plus "someone already offered that exact
  digest", keeps a crowded channel from all answering at once.
- **Several peers:** after one peer is done, any other offer whose digest
  still differs from ours is pulled next (up to 3 peers per sync).
- **Offline peers:** if the peer goes quiet for 20 s or logs off (its
  "No player named…" system line is hidden), the next offer is tried. If
  none is left, the sync asks again 10 s later (twice at most per zone
  visit). Players with the same stones stayed quiet the first time, so one
  of them answers now.
- **Merging** (`Store:Merge`): new stones are accepted from anyone and
  marked `verified` only when they come first-hand from the author. An
  **existing** stone can only be changed or deleted **first-hand by its
  author**, so a relay can't forge an edit. Your own stones are never
  overwritten or requested. A relayed tombstone for a stone you've never
  seen is kept, so a stale copy can't resurrect it later. Every record is
  validated by `Codec.DecodeStone` first (id belongs to the author, text
  ≤ 140 characters, sketch format and data, numbers, position).
- **`/soap net sync`** shows the zone, its fingerprint, any sync in progress
  and recent results; `/soap net sync now` asks again immediately. (Before
  the companion app this was `/soap sync`, which now syncs with the companion.)

**Simulated-network results** (`tests/sync.test.lua`, with WoW Forever's
measured latency and allowance): a newcomer pulled 25 stones (5 sketches)
from one player in **43 s over 46 messages** (35 carrying stones), with no
refused or oversized messages. Offline peers, forged edits, deletions,
Retail/Forever separation, local test stones and multi-peer pulls all
behave as described.

**Live drops:** dropping a stone posts `NS zone=1456 id=… version=1` on the
channel. Players in that zone fetch it by whisper; everyone else ignores it.
Edits (`version+1`) and deletes (tombstones, below) are announced the same way.

---

## Local storage

- Stones stay in `SoapstoneDB` (per account, per client), keyed by id, each
  tagged with its flavour and zone (see `Store.lua` for the exact shape).
- **Caps:** for example the newest 200 stones per zone and ~5,000 in total,
  evicting the least recently visited zones first. **Your own stones are never
  evicted**; authors are always a source for their own stones.
- Pins and proximity checks only look at stones **near the player**, via a
  spatial index (500-yard cells per continent). This works across zone
  borders, unlike filtering by current zone.

---

## Edits and deletes

- Every stone has a `version`, starting at 1. Higher wins.
- **Edits** are accepted only first-hand, from a message whose sender key
  matches the stone's `authorKey`, and only inside the 5-minute window
  measured from the stone's drop time.
- **Deletes** become **tombstones** (`id`, `version`, deleted = true), kept
  for a while (say 7 days) so a stale copy elsewhere can't bring the stone
  back.

---

## Abuse limits (no moderation yet)

- Size limits: text ≤ 140 characters, sketch ≤ the 160×60 format, message
  fields validated.
- Per author: at most N live stones per zone (N to be set, perhaps 10).
- Flooding: a sender over the rate budget is ignored for the session.
- Malformed or wrong-flavour messages are dropped silently.

---

## Honest limits

- **Stones only persist while someone holds them.** A stone can be fetched
  while at least one online Soapstone player has it. Early on, with few
  players, you'll mostly see stones from people who are online or were
  recently in the zone. Coverage grows with players.
- **No global view.** There's no way to ask "how many stones exist in
  Azeroth"; each player only knows the zones they've synced.
- **Channel ownership.** The first player into a custom channel becomes its
  owner and could set a password or kick people. Anyone reading the addon
  code knows the channel name. We may need a fallback name or rotation.
- **Scale.** On a realmless world one channel might hold the whole
  population, and every broadcast reaches everyone, so broadcasts stay tiny
  and bulk goes by whisper.
- **Instance restrictions.** Recent retail builds limit addon messages inside
  instances during encounters. Soapstone is an open-world addon, so this
  should rarely matter.

---

## Rollout

1. **Network test build** *(this step)*: join the hidden channel;
   `/soap net` status, ping, burst and log; the flavour and identity helpers;
   stones record "Mad Decent" / `Mad-Decent`. No stone syncing.
2. **Data model** *(done: `Store.lua`, schema 2)*: stones keyed by id with
   `v`, `flavor` and `zone`; tombstones (7 days); an outbox; caps of 200
   others' stones per zone and 5,000 in total (least recently visited zones
   go first, your own never); a spatial index in 500-yard cells so the
   minimap and proximity checks only look nearby; "mine" is
   `authorKey == your key` (the old account-wide flag only counts for
   stones from before names were stored); test stones are `localOnly`; and
   `Net:Enqueue`, a send queue that stays inside the measured allowance.
   Still to add when step 3 needs them: `via` / `verified`.
3. **Zone sync** *(built; verified on the simulated network, not yet
   between two real players)*: the protocol above, with chunking, pacing,
   multi-peer pulls, retry and first-hand-only changes.
4. **Live drops, edits and deletes** over the channel.
5. **Abuse limits and tuning** from real traffic.

## Test plan for step 1

### Solo: `/soap net selftest` (one character)

Channel addon messages come back to their sender through the server, and a
character can whisper itself, so one character covers most of the unknowns:

| Checks | Tells us |
|---|---|
| Channel message comes back | T1: the hidden channel works on WoW Forever |
| How your name shows on the way back | T3: sender format (`Mad-Decent` / `Mad Decent` / `Mad`) |
| Whispers to yourself as `Mad-Decent`, `Mad Decent`, `Mad` | T5: which name form works as a whisper target |
| Guild (if in one), say, yell | T6: which fallback routes work |
| 30 messages at once, counting how many return | T4: client refusals (result codes) and server-side drops |

`/soap net pacetest [per second] [seconds]` (default 4/s for 20 s) spends
the burst first, then sends steadily; what the client still accepts is the
**sustained refill rate**, which sets how fast a zone can sync.

The only thing it can't answer is **T2, reach**: whether a player elsewhere
in the realmless world hears you. That needs a second player.

### With a second player

Needs **two characters online at once** (a friend, or a second account),
both running the test build.

| # | Test | How | Tells us |
|---|---|---|---|
| T1 | Channel joins and stays hidden | `/soap net` on both | Channel works at all on WoW Forever |
| T2 | Reach | A: `/soap net ping`, with B nearby, then far away (other zone/continent) | Whether the channel spans the realmless world |
| T3 | Sender format | Read the "reply from …" lines | Whether names arrive as `Mad-Decent`, `Mad Decent` or `Mad` |
| T4 | Throttle | `/soap net burst 20`, then `50` | Where the client refuses (result codes) and what arrives |
| T5 | Whisper replies | Pings are answered by whisper | Whether whispers work with the sender string as given |
| T6 | Fallbacks | `/soap net ping party`, `guild`, `yell` | Which other routes work if the channel doesn't |
