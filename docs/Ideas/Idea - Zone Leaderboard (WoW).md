#idea, #soapstone, #wow, #ratings

> **WoW-specific.** This idea is for the Soapstone-WoW addon. It builds on
> the addon's Appraise / Disparage ratings and its player-to-player network,
> and doesn't carry over to the phone app as written.

## Zone Leaderboard: Most Appraised in the Zone

A per-zone board of the stones players have appraised most. The board never
shows what a stone says: it shows the score, who left it, and which way to
walk. To find out *why* a stone is number one, you have to go and stand
where it was left.

It turns ratings into a reason to travel: every zone gets a short
pilgrimage list, and every author gets a shot at being the stone people
cross the map for.

---

### The catch: scores are local today

A stone's score is only what this client knows: the author's own appraisal
plus the judgements cast by your characters on this account
(`Soapstone/Stones.lua`, "a server would add everyone else's"). Votes are
never shared, so a board built today would mostly list your own stones at
score 1.

So this is two pieces of work: **sharing votes**, then **the board**.

The data model already fits. `db.ratings[id][characterKey]` holds one
judgement per character, kept apart from the stone record
(`Soapstone/Store.lua`), so other players' votes can go straight into it.

---

### Part 1: Sharing votes

**Live votes.** Appraising, disparaging or withdrawing posts a tiny
announcement on the channel, like `NS` does for drops:

```
NV zone id value        value = 1, 0 or -1   (~60 bytes)
```

Players in that zone record the vote under the sender's key. Everyone else
ignores it. Votes are rare, so this barely touches the ~1 message/s budget.

**Catch-up in zone sync.** Votes become their own records in zone sync,
`id:voter:value`, included in the bucket fingerprints the way tombstones
are, so an up-to-date zone still costs one broadcast. Rough cost: 200
stones × ~3 votes × ~20 bytes ≈ 12 KB ≈ 50 messages from one peer. Send
stones first and votes after, so the minimap fills in before the scores do.

**Trust.** A vote that arrives first-hand from the voter can't be forged:
the server sets the sender. A vote relayed by someone else could name a
voter who never voted. Options:

| Rule | Forgery-proof | Scores grow when |
|---|---|---|
| **Strict**: first-hand votes only | Yes | Voter and you are online at the same time |
| **Known voters** *(recommended)*: relayed votes count only if you've had at least one first-hand message from that voter, ever | Mostly | Anyone who has seen the vote passes it on |
| **Open**: count every relayed vote | No | Fastest, and easy to stuff |

Known voters proves the character exists and runs Soapstone. Alts can
still pad a score. For a board with no stakes, that's acceptable.

The author's own vote keeps its current rule: it counts as 1 or 0, never
below.

---

### Part 2: The board

**Sealed, like the stones.** Each row shows score, author, kind (message or
sketch), distance and compass direction, and whether you've read it:

```
 Most appraised in Elwynn Forest              Top · Rising
 1. ★ 14   Osha Compliant · sketch      1.2 km NE
 2.    9   Mad Decent · message         read ✓
 3.    7   Grimbo · message             340 yd S
```

- **Where:** a second tab on the right-click list (today "nearest 10"),
  and `/soap top`.
- **Top / Rising:** all-time score, and score gained in the last 7 days, so
  new stones can compete with old favourites.
- **Minimum to appear:** 3 different appraisers, so a quiet zone doesn't
  fill up with score-1 stones.
- **Zone key:** the same zone-level map ID zone sync uses.

**The crowned stone.** The zone's number-one stone gets its own minimap pin
and a longer reach: its "somewhere close" cue fires from ~300 yd instead of
150. The best stones call you from further away.

**The author moment.** When one of your stones takes the top spot:
"Your soapstone in The Barrens is the most appraised in the zone." This is
the part most likely to get screenshotted.

**Not doing: a "most disparaged" board.** Funny, but it rewards trolling,
and there's no moderation yet.

---

### Build order

1. **Vote sharing:** `NV` live votes, vote records in zone sync, the
   known-voter rule, tests on the simulated network. This alone makes the
   existing gold / faded pins and the "Appraisals: N" count mean something.
2. **Board tab and `/soap top`**, sealed rows only.
3. **Crowned pin**, longer reach, and the author notification.

---

### Open questions

- Once you've read a stone, may the board show its text, or does it always
  stay sealed?
- Strict or known-voter trust?
- An authors board too (most appraised writers per zone), or stones only?
- Should Rising use a fixed 7-day window or decay older votes gradually?

---

### Related

- [[Idea - Quests (Pilgrimage System)]]: the board is a light,
  player-made version of a pilgrimage.
- [[Idea - First Discovery Bonus]]: "first to read the #1 stone" could be a
  moment of its own.
- `docs/Sharing - Architecture.md`: zone sync, message budget, identity.
