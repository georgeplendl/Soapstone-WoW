#idea, #soapstone, #wow, #network

> **WoW-specific.** This idea is for the Soapstone-WoW addon's
> player-to-player network (`docs/Sharing - Architecture.md`). It doesn't
> carry over to the phone app.
>
> **Status (2026-10-06): on hold.** The companion app now shares stones, and
> the player-to-player network is opt-in and due to be trimmed to live
> drops, so most of this matters only if that live channel needs it.
>
> The ideas come from studying how another WoW Forever addon, Happy Camper,
> runs its own network. Only the general approaches are borrowed. No code,
> channel or traffic is shared with it, and Soapstone stays on its own
> network.

## Network Resilience: Four Small Hardening Ideas

Four independent changes. Each one targets a weakness already listed under
*Honest limits* in the architecture doc, and each can ship on its own.

1. **Backup channels**: survive someone taking over `SoapstoneNet`.
2. **Coalesced replies**: one answer serves everyone who just asked.
3. **Version and user census**: "a newer Soapstone exists" and "about N
   players use Soapstone", with no extra messages.
4. **Additive wire format**: grow messages without bumping `S1`.

---

### 1. Backup channels

**The problem.** The first player into a custom channel owns it. Anyone who
reads our code knows the name `SoapstoneNet`, so they could join first, set
a password or ban people, and cut everyone else off.

**The idea.** Ship a fixed, ordered list of channel names in the addon:

```
SoapstoneNet, SoapstoneNetB, SoapstoneNetC, SoapstoneNetD, SoapstoneNetE
```

- Every copy tries them **in the same order**, so everyone who gets locked
  out of the same channel ends up in the same backup.
- Joining fails because of a wrong password or a ban → try the next name.
  Kicked or banned while inside → leave and move on.
- **Bridging:** a player who is still in the main channel *also* joins the
  backup when they hear that someone was locked out (or when the backup has
  members), and passes on channel broadcasts (`ZQ`, `ZH`, `NS`) between the
  two. Whispers don't need bridging: they work no matter which channel
  either player is in.
- To limit the extra traffic, a bridge only re-sends *announcements*,
  never bulk data, and drops anything it has already passed on (keyed by
  sender + message).

**What to watch for.**

- Each extra channel shifts the player's channel numbers. Join backups
  only when needed, and keep the existing `JOIN_DELAY` so General and Trade
  keep `/1` and `/2`.
- Every hidden channel must be removed from all chat windows, as
  `SoapstoneNet` is today.
- `/soap net` should show which channel you're in and any bridges.

**Cost.** Nothing when the main channel is healthy. When it's taken, a
handful of bridging players each spend part of their message budget on
re-sending announcements.

---

### 2. Coalesced replies

**The problem.** Today a `ZQ` gets a `ZH` offer after a random 0.4–2.5 s,
and a peer stays quiet if someone already offered the same digest. That
covers a crowd of *answerers*. It doesn't cover a crowd of *askers*: when a
group logs in or zones in together, the same well-stocked peer can be asked
again and again.

**The idea.** Treat a broadcast reply as an answer to everyone who asked
recently, not just to the asker who triggered it.

- A peer sends **at most one `ZH` per zone every N seconds** (start with
  30). A `ZQ` that arrives inside that window is answered when the window
  ends, with a single reply that covers everyone who asked meanwhile.
- A reply that is already waiting covers new questions too: no second one
  is queued.
- **Per-asker cooldown:** answer the same player's `ZQ` for the same zone
  at most every 2 minutes. That stops one player (or a buggy copy)
  from spending everyone's budget.
- Because `ZH` goes to the channel, every asker hears it and can start
  `ZL` with that peer, so no one is left waiting.

**Fits with what exists.** Keeps the random backoff and the "same digest
already offered" rule. It's the same idea applied on the asking side.

---

### 3. Version and user census

**The problem.** Players on old copies never learn there's an update. And
nobody can tell whether *anyone else* is using Soapstone, which is the main
reason the network feels empty early on.

**The idea.** Add two trailing fields to the `ZQ` every client already
sends when it enters a zone or after login (see idea 4):

```
ZQ zone digest count  version  knownUsers
```

**Census.** Each client keeps an account-wide list of Soapstone players it
has heard from: key, first seen, last seen, version. Its own count goes out
in `knownUsers`, and it also remembers the **largest count anyone has
reported**. `/soap net` can then say:

```
You've met 14 Soapstone players. The largest count reported is about 60.
```

The number is never exact (players only count who they've heard), but it
shows that the network is alive, and it costs no extra messages.

**Update notice.** When a newer `version` is heard, print one line in the
player's own chat (once a session): "A newer Soapstone (0.5.0) is out." To
keep it from being spoofed:

- Believe a newer version only once **two different players** report it.
- Ignore claims more than one major version ahead.
- Development copies (non-plain versions like `0.5.0-dev`, or ones with a
  branch in `BuildInfo.lua`) neither trigger nor cause notices.
- Remember that the notice was shown, and clear that when the player's own
  version changes.

**Privacy.** The list holds only character names the player already heard
on the channel, stays in their own saved variables and is never sent. Only
the count leaves the client.

---

### 4. Additive wire format

**The problem.** The `S1` header means any incompatible change needs `S2`,
and `S1` and `S2` players can't hear each other at all. That splits an
already small network.

**The idea.** Make a rule of what the code mostly does already:

- **New fields only go at the end.** Lua handlers already ignore extra
  trailing arguments, so older copies read a longer message fine.
- **Unknown message types are ignored silently.** `Net.lua` already does
  this, since there's no handler for them. Write it down so nobody "fixes"
  it later.
- **Missing trailing fields mean "older sender"**, and each handler
  defaults them (e.g. `version` absent → unknown).
- **Never reuse or reorder a field.** A field that's no longer used is sent
  empty.
- Bump to `S2` only for a change that *can't* be additive (a new record
  encoding in `Codec.lua`, a change to how fingerprints are computed).

**Write it down** in `docs/Sharing - Architecture.md` under *Transport*,
and add a test in `tests/net.test.lua`: a message with extra trailing
fields and an unknown type both pass without errors.

---

### Build order

1. **Additive format rule** and its test. It's mostly documentation, and
   idea 3 depends on it.
2. **Census and update notice** on `ZQ`. Small, and it answers "is anyone
   else out there?", which matters most right now.
3. **Coalesced replies**, tuned once real traffic exists (rollout step 5).
4. **Backup channels**, built and tested on the simulated network now, so
   it's ready before anyone tries a takeover.

---

### Open questions

- How long do backup channels stay joined after the main one recovers, or
  does a player stay in the backup for the rest of the session?
- Should the census include players heard only through whispers, or only
  on the channel?
- Should the update notice name where to download it (CurseForge, GitHub)?
- Is 30 s the right reply window, given the ~675 ms round trip and the
  1 message/s budget?

---

### Related

- `docs/Sharing - Architecture.md`: transport, zone sync, message budget,
  and *Honest limits* (channel ownership, scale).
- [[Idea - Zone Leaderboard (WoW)]]: vote sharing adds channel traffic,
  so it benefits from coalesced replies.
