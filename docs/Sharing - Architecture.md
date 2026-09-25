# Sharing — Architecture

How Soapstone stones get from the player who drops them to every other player
who walks past, with nothing to install but the addon.

**Status:** design agreed with George on 2026-09-25. Step 1 (the network test
build) is in progress; nothing syncs stones yet.

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

## Zone sync (step 3)

The **zone key** is the zone-level map ID. From `C_Map.GetBestMapForUnit`,
climb parents until the map type is *Zone*; Thunder Bluff is `1456`.

When you enter a zone:

```
you ──(channel)──►  ZQ   zone=1456  digest=a91f  count=12
                         "who has Thunder Bluff? here's a fingerprint of mine"

peers whose digest differs wait a random 0–2 s; the first to answer posts:
peer ─(channel)──►  ZH   zone=1456  digest=77c0  count=19
                    everyone else with the same digest hears it and stays quiet

you ──(whisper)──►  ZL   zone=1456                     "send your list"
peer ─(whisper)──►  ZI   id:version, id:version, …     (in parts)
you ──(whisper)──►  ZG   id, id, …                     "send me these"
peer ─(whisper)──►  ST   <stone>, …                    (in parts, paced)
```

- **Digest:** a short hash of the sorted `id:version` list for that zone, so
  two players can tell whether they agree without sending the list.
- **Suppression:** random backoff plus "someone already answered with that
  digest" keeps a crowded channel from replying all at once.
- **Retry:** if the answering peer leaves mid-transfer, ask again. A second
  pass with another peer catches anything the first one lacked.

**Live drops:** dropping a stone posts `NS zone=1456 id=… version=1` on the
channel. Players in that zone fetch it by whisper; everyone else ignores it.
Edits (`version+1`) and deletes (tombstones, below) are announced the same way.

---

## Local storage

- Stones stay in `SoapstoneDB` (per account, per client), grouped by flavour
  and zone.
- **Caps:** for example the newest 200 stones per zone and ~5,000 in total,
  evicting the least recently visited zones first. **Your own stones are never
  evicted**; authors are always a source for their own stones.
- Pins and proximity checks only consider the **current zone**.

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
2. **Data model:** zone key, `version`, tombstones, `flavor`, `via`, an
   outbox, and the per-zone and total caps. Also: "mine" must mean
   `authorKey == your key`, not the account-wide `mine` flag. Today any
   character on the account can edit another's fresh stone.
3. **Zone sync:** the protocol above, with chunking and pacing.
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
