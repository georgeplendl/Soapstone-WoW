#idea, #soapstone, #gamification

## First Discovery Bonus — Breaking the Seal

The first user to listen to a newly dropped stone earns a reward. Zero-listen stones are "unbroken" — once someone plays them, they're permanently marked as discovered, and that user's name is attached to the moment.

Inspired directly by Dark Souls: the first player to leave a message in a new area, or the first to kill a boss on a fresh server, carries a quiet prestige. This mechanic gives Soapstone that same energy.

---

### Core Mechanic

- A stone with **0 listens** is in an **Unbroken** state
- The first user to open the listening pane and play it earns a **capsule pull** (pin skin reward)
- A "You're the first to hear this." moment triggers — a brief screen animation, haptic pulse, and the pull reward
- The listening pane permanently displays **"First heard by @username"** in the metadata row for all future listeners

The dropper does **not** count as a first listener — they already know what it says.

---

### Visual Differentiation on the Map

Unbroken stones look different from played ones:

- A subtle **shimmer or bright pulse** on the pin — visually distinct from the standard sonar animation on the user's location dot
- Once broken, the pin returns to its standard appearance
- This creates a passive hunt: glancing at the map, a shimmering pin is a target

The nearby list cards could also surface this — a small "NEW" or glyph badge on undiscovered stones so active users know to move fast.

---

### Reward Rarity Scaling

Not all first discoveries are equal. Rarity of the capsule pull scales by context:

| Condition | Pull Tier |
|---|---|
| Discovered within 1 hour of drop | Common pull |
| Discovered within 10 minutes of drop | Uncommon pull |
| Discovered in a location with no other stones nearby (remote drop) | Rare pull |
| Discovered within 5 minutes AND remote location | Legendary pull |

This rewards both **speed** (active explorers checking the map in real time) and **range** (users who walk to places nobody else goes).

---

### The Social Layer

"First heard by @username" in the pane metadata is small but meaningful:

- It's a permanent, visible record tied to that stone forever
- Other listeners see it and know someone was there first
- Over time, prolific first-discoverers build a quiet reputation — their name appearing across many stones around town
- Could surface as a stat on the Profile screen: **"First discoveries: 34"**

This is a non-competitive leaderboard. No rankings, no pressure — just a trace of who was there.

---

### Edge Cases

- **Simultaneous discovery:** Two users open the stone at the same instant. Server-side first-write wins — whichever play event hits the backend first claims it. No tie.
- **Accidental opens:** If the pane opens but the user immediately closes it before audio plays, it should **not** count as a listen. Trigger on actual playback start, not pane open.
- **Remote/rural stones:** Stones dropped in low-traffic areas may go undiscovered for days or weeks. That's fine — the reward is waiting. Could even add intrigue: a shimmering pin that's been unbroken for 3 weeks is its own kind of mystery.
- **Stone expiry:** If stones have a TTL (e.g., 30 days), an unbroken stone that expires without ever being heard is just gone — no reward, no record. A small tragedy that fits the aesthetic.

---

### Open Questions

1. Should the "First heard by" credit be opt-out for privacy-conscious users?
2. Does the first discovery reward stack with other pull sources (e.g., Cairn pulls, drop pulls), or share a daily cap?
3. Is the shimmer visible on locked pins (outside the gate), making remote unbroken stones visible as targets from a distance?
4. Should a "First Discoveries" stat appear on the public Profile, or stay private?
5. Is there a leaderboard — even a local/city-scoped one — for top discoverers, or does that undercut the low-pressure vibe?
