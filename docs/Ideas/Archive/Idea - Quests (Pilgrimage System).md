#idea, #soapstone, #gamification

## Quests — The Pilgrimage System

Quests are directed challenges that reward users for going somewhere, doing something, or experiencing Soapstone in a new way. They sit between passive rewards (Cairn pickups, First Discovery) and intentional exploration — giving users a reason to leave the house with a destination in mind.

The long-form multi-stop variant — visiting a sequence of locations — is called a **Pilgrimage**.

---

### Quest Types

#### 1. Daily Quests
Simple, refreshes every 24 hours. Designed to be completable in a single outing.

Examples:
- "Drop a stone somewhere you've never dropped one before." → Common pull
- "Listen to 3 stones today." → Common pull
- "Be within 0.25 miles of moving water when you drop a stone." → Uncommon pull
- "Drop a stone after sunset." → Uncommon pull (time-gated)

#### 2. Weekly Quests
Harder, longer horizon. Rewards effort over multiple outings.

Examples:
- "Drop stones in 3 different neighborhoods this week." → Rare pull
- "Earn a First Discovery 2 times this week." → Rare pull
- "Listen to 15 stones this week." → Uncommon pull
- "Drop a stone more than 5 miles from your home location." → Rare pull

#### 3. Pilgrimages
Multi-stop, city-specific routes curated by the Soapstone team. A Pilgrimage chains together 3–7 real-world locations — Cairns, landmarks, or location types — that the user visits in any order (or a fixed sequence, TBD).

Examples:
- **The Harbor Route** — Visit 4 waterfront spots in the city. Drop a stone at each.
- **High Ground** — Drop stones at 3 of the highest elevation points within 20 miles.
- **Old Town** — Visit 5 locations designated as historic sites.
- **The Grid** — Drop a stone in each of 6 distinct neighborhoods.

Completing a Pilgrimage earns a **route-exclusive Legendary skin** — unobtainable any other way. The skin is visually tied to the route (a harbor route skin looks different from an elevation route skin).

---

### Location Classification

Quests that reference location types rely on a classification layer — how the app knows you're "near water" or "at a historic site." A few approaches:

- **OpenStreetMap tags** — water bodies, parks, peaks, and historic landmarks are all tagged in OSM. Can derive location type from GPS + OSM without any manual curation.
- **Cairn tier** — Cairns already have a tier system (Common / Notable / Legendary). Quests can reference Cairn tiers directly: "Drop a stone at a Notable or higher Cairn."
- **Elevation API** — Elevation data is publicly available. "Above 500ft" or "highest point in your county" are derivable.
- **Manual tagging** — For Pilgrimages specifically, the Soapstone team hand-curates the stops.

---

### Reward Structure

| Quest Type | Default Reward | Notes |
|---|---|---|
| Daily | Common pull | Always completable |
| Weekly | Rare pull | May require planning |
| Pilgrimage | Legendary pull + route skin | Route skin is exclusive |

Quest-exclusive skins should never enter the standard capsule pool. The only way to get a Pilgrimage skin is to walk the route. This keeps them meaningful long-term.

---

### Quest UI

Quests live in their own tab or section — likely within the **Activity** screen or a dedicated **Quests** tab in the bottom bar. *(Flag: tab bar currently has 4 items — adding a 5th for Quests may require rethinking the nav structure.)*

Each quest card shows:
- What the quest asks you to do
- Progress indicator (0 / 3 neighborhoods)
- Reward preview (blurred or silhouetted skin)
- Time remaining (for daily/weekly)

Pilgrimages show a mini-map of the route with stops marked — checked off as you complete each one. Completing the final stop triggers the Legendary reward screen.

---

### Tone and Naming

Quests should feel like discoveries, not chores. The copy matters:

- Avoid: "Complete 3 tasks to earn a reward."
- Prefer: "The city at night sounds different. Drop a stone after dark."

Each quest should read like an invitation, not an assignment. The Dark Souls parallel: the game never says "go to the swamp." It leaves messages, hints, and environmental cues — you find the swamp yourself and feel rewarded for doing so.

Pilgrimage names should be evocative and local: **The Harbor Route**, **The Ridge**, **Old Quarters**, **The Long Way Round**. They should feel like something a local would name a walking trail, not a game achievement.

---

### Interaction with Other Systems

- **Cairns**: Pilgrimages can use Cairns as stops — visiting a Cairn and tapping it satisfies that leg of the route.
- **First Discovery Bonus**: "Earn a First Discovery" is a natural weekly quest objective — links the two systems without requiring new mechanics.
- **Stone TTL**: If stones expire after 30 days, a quest like "Drop stones that survive 2 weeks" (i.e., get enough listens to be extended) could be a long-horizon challenge.

---

### Open Questions

1. Are Pilgrimages city-specific at launch, or is there a global set available everywhere?
2. Fixed sequence (visit stops in order) or open order for Pilgrimages?
3. Does a Pilgrimage require you to *drop a stone* at each stop, or just *visit* (be within range)?
4. How many active quests can a user have at once — all visible simultaneously, or one daily + one weekly + one pilgrimage?
5. Can Pilgrimages expire, or are they always available until completed?
6. Should there be a social element — friends on the same Pilgrimage, or a count of how many users have completed a route?
7. Does the Quest system warrant its own tab in the nav bar, or does it live inside Activity/Profile?
