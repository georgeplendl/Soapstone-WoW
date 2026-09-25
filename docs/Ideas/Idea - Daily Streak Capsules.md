#idea, #soapstone, #gamification

## Daily Streak Capsules — Laying Stones

A daily streak that rewards showing up and participating in any meaningful way. The core design principle: **reward behavior, not geography**. A user in a dense city and a user in a rural town should have equal access to the streak — what matters is that they opened the app and engaged, not whether there happened to be stones nearby.

---

### What Counts as a Streak Day

Any one of the following keeps the streak alive:

| Action | Streak? | Pull Quality |
|---|---|---|
| Open the app and view the map (10+ sec) | Yes | Common |
| Drop a stone | Yes | Uncommon |
| Listen to a stone | Yes | Uncommon |
| Drop a stone AND listen to one | Yes | Rare |

The minimum bar — opening the map — is intentionally low. The point is to reward people who come back daily, not to gatekeep based on what's around them. Higher engagement on a given day earns a better pull from that day's reward, but never invalidates the streak itself.

This also naturally solves the early-growth problem: when stone density is low everywhere, users can still build streaks from day one without the app feeling dead.

---

### Streak Milestones

Milestones are where the real rewards live. Hitting a milestone earns a capsule pull one tier higher than normal:

| Milestone | Bonus |
|---|---|
| 3 days | Uncommon pull |
| 7 days | Rare pull |
| 14 days | Rare pull |
| 30 days | Legendary pull |
| 60 days | Legendary pull + exclusive streak skin |
| 100 days | Legendary pull + exclusive streak skin (distinct from 60-day) |

The **60-day and 100-day skins** should be visually tied to the streak — something that communicates time and commitment. A worn, weathered stone aesthetic. A pin that looks like it's been sitting in the earth a long time.

These skins should never enter any other reward pool. The only way to get them is the streak.

---

### Grace Days (Streak Freeze)

Missing one day shouldn't erase a 47-day streak. Users earn **Grace Days** through normal play — they bank automatically and are consumed silently when a day is missed.

- Earn 1 Grace Day for every 7-day milestone reached
- Maximum of 2 Grace Days stored at a time
- Grace Days are consumed automatically — no UI prompt, no decision to make
- If a Grace Day is used, a subtle note appears the next time the app opens: "Your streak continued — one stone in reserve."

This is not purchasable. It's earned through the streak itself, which means long streaks become self-reinforcing without requiring spending.

---

### Streak UI

The streak lives on the **Profile screen** — not surfaced aggressively on the home screen. It should feel like something you notice and appreciate, not something that guilts you every time you open the app.

- A small flame or worn-stone glyph next to the username, showing the current streak count
- Tapping it opens a simple streak card: current count, next milestone, grace days remaining
- On milestone days, a brief celebratory moment on app open — understated, not confetti

The tone should be quiet pride, not Duolingo-level anxiety.

---

### What to Avoid

- **Don't make the streak the first thing users see.** It shouldn't dominate the home screen or feel like a daily obligation.
- **Don't require listening.** As noted above, geography is not behavior. A user who opens the app every day in a low-density area is just as loyal as one surrounded by stones.
- **Don't make Grace Days purchasable.** Monetizing streak protection is a fast path to dark-pattern territory. Keep it earned.
- **Don't inflate milestones with common pulls.** If every milestone gives a common pull, the system loses meaning. Milestones should feel like events.

---

### Interaction with Other Systems

- **Cairn pulls and Quest pulls are separate** from streak pulls — they don't share a cap and don't interfere with each other. Streak rewards are additive.
- **Dropping a stone** satisfies both the streak and potentially a daily Quest objective — no double-dipping friction.
- **First Discovery** can count as a streak day at the Uncommon tier — going out and finding something new is exactly the behavior worth rewarding.

---

### Open Questions

1. Does the streak reset at midnight local time, or on a rolling 24-hour window from last engagement?
2. Should the streak count be visible to other users (on the public profile), or private?
3. Is there a maximum Grace Day bank, or does it scale with streak length?
4. Should there be a "comeback" mechanic — if a user breaks a long streak and returns, do they get any acknowledgment of their prior streak ("You had a 45-day streak — welcome back")?
5. At very long streaks (100+ days), does the reward cadence change, or does the 30-day Legendary pull just repeat indefinitely?
