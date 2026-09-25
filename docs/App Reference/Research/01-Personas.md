# Soapstone — User Personas

**Author:** UX Research (discovery cycle)
**Date:** 2026-06-06
**Status:** Provisional / Proto-personas
**Grounding:** Product concept (DESIGN.md, App Specification), stated use cases (Initial Ideas), competitive set (Autio, Echoes, Yik Yak, Snap Map, Gowalla/Foursquare).

> ⚠️ **These are proto-personas, not research-validated personas.** No interviews, surveys, or analytics exist yet. They are hypotheses derived from the product vision and analogous products. Treat behaviors and frustrations as *assumptions to validate*, not findings. See "Research Gaps" at the end.

---

## Behavioral variables (the axes the personas spread across)

Before naming personas, the four behavioral spectrums that matter most for Soapstone:

| Variable | Low end ←——————→ High end |
|---|---|
| **Create vs. consume** | Pure listener ←→ Prolific dropper |
| **Motivation** | Utility (tips, info) ←→ Expression / ambient connection |
| **Place attachment** | Passing through ←→ Rooted in a place |
| **Gamification pull** | Indifferent to rewards ←→ Badge/streak-driven completionist |
| **Social posture** | Wants anonymity / lurk ←→ Wants recognition / following |

The personas below are deliberately placed at different points on these axes.

---

## Persona 1 — Maya, "The Wanderer"  ⭐ PRIMARY

> *"I want the city to whisper back at me."*

**Photo:** Late-20s woman, headphones around her neck, photographed mid-stride on a sidewalk with a coffee, looking off-frame at something.

- **Age / context:** 27, lives in a dense, walkable city (Lisbon / Brooklyn / Melbourne archetype). Renter, lives alone or with roommates.
- **Occupation:** Junior UX designer / barista-by-day creative. Modest income, lots of unstructured walking time.
- **Tech comfort:** High. Early adopter. Played *Dark Souls*; the soapstone metaphor lands instantly for her.

**Goals**
- *Functional:* Discover the texture of places she already walks through — what happened *here*.
- *Emotional:* Serendipity and a low-stakes sense of being connected to strangers without the performance of social media.
- *Social:* Leave a trace. Feel like she's part of an ambient, anonymous-feeling community.

**Frustrations**
- Mainstream social apps feel performative, algorithmic, and exhausting.
- Geo-tagged content (Snap Map, etc.) is visual, polished, and tied to identity — she wants something rawer and more ephemeral.
- Nothing today rewards the act of *physically being somewhere*.

**Behaviors today**
- Walks everywhere with one earbud in. Uses Strava, Letterboxd, BeReal — apps with a "ritual" and a community vibe.
- Reads plaques, graffiti, and stickers on lampposts. She already hunts for place-based meaning.

**Day in the life**
> On her walk to work Maya opens Soapstone, sees three pulsing dots within her mile. One is 4 minutes old, two streets over. She detours, walks into range, and a stranger's voice — half-laughing — describes the dog they just saw wearing a raincoat. She smiles, holds the FAB, and leaves a 12-second reply pinned to the same corner. Total interaction: 90 seconds. No likes, no followers, no pressure.

**Design implications**
- The **map + proximity gate IS the product** for her — protect its purity; don't bury it under feeds.
- The **"walk into range to unlock"** friction is a *feature*, not a cost — it's the serendipity engine. GPS radar / navigation toward locked dots matters.
- Anonymity-leaning identity (random usernames "Sleepy Skunk") fits her better than real-name profiles.
- Recording must be **frictionless and intentional** — tap-and-hold-to-drop nails the ritual she craves.

**Why she's primary:** She is the early adopter who will *seed content* and tolerate an empty map. The core mechanic was designed for her mindset. If Soapstone doesn't delight Maya, the network never reaches density for anyone else.

---

## Persona 2 — Darnell, "The Local Tipper"

> *"Best taco here is the one that's NOT on the menu — let me tell you."*

**Photo:** Mid-30s man, ball cap, leaning on a counter at a food hall, mid-sentence.

- **Age / context:** 35, lives in the same neighborhood for 8 years. Married, one kid. Knows every corner.
- **Occupation:** Regional sales rep — drives and walks his city constantly; meets people.
- **Tech comfort:** Medium-high. Power user of Google Maps reviews, Yelp, Foursquare/Swarm back in the day. Misses Gowalla badges.

**Goals**
- *Functional:* Share genuinely useful, hyperlocal knowledge — the menu hack, the quiet park bench, the shortcut.
- *Emotional:* Be the helpful local; quiet pride of authorship.
- *Social:* Light recognition (play counts, "helpful" reactions, badges) without a full social-media identity.

**Frustrations**
- Text reviews are slow to write and feel sterile; his *voice* carries the tip better ("you gotta ask for it like THIS").
- Yelp/Google reviews are global and permanent; he wants something local and in-the-moment.
- Wants proof his tips are heard (play counts, reactions).

**Behaviors today**
- Already leaves Google reviews and texts friends "go here, get this."
- Motivated by badges/streaks (the Idea docs' gacha & "Dropped Soapstones in 50 cities" ideas are aimed squarely at him).

**Day in the life**
> Leaving his favorite lunch spot, Darnell gets a notification: "Drop a stone about where you just ate?" He holds the button: "If you're standing here — order the al pastor, but ask for it on a flour tortilla, trust me." Drops it on the doorstep. Over the week he watches the play count tick to 40 and earns a "Tastemaker" badge.

**Design implications**
- He's the **utility engine** — his stones give listeners a *reason* to value the app beyond novelty.
- **Play counts, reactions ("Helpful/Funny"), and badges** matter a lot to him (validates the gamification roadmap).
- "Drop a stone where you just were" **contextual notifications** (the restaurant-reminder idea) directly serve him.
- Tension to manage: his utility-posting could clash with Maya's ambient/anonymous vibe. **Layers/tags** (the roadmap idea) may be how both coexist.

---

## Persona 3 — Priya, "The Listener"

> *"I don't really post… I just like hearing that someone else was here."*

**Photo:** Early-20s woman on a bus, hood up, earbuds in, looking out the window.

- **Age / context:** 21, university student, commutes by transit, often feels a low hum of urban loneliness.
- **Occupation:** Student, part-time retail.
- **Tech comfort:** High (digital native) but socially **lurk-first** — consumes far more than she creates everywhere (TikTok, Reddit).

**Goals**
- *Functional:* Pass dead time (commutes, waiting) with something local and human.
- *Emotional:* Feel less alone — ambient company, a sense that strangers share her space.
- *Social:* Connection **without exposure.** Posting feels vulnerable; listening feels safe.

**Frustrations**
- Posting anything publicly is anxiety-inducing — she fears judgment.
- Empty maps / dead apps bore her instantly (she has zero tolerance for a cold-start ghost town).
- Doesn't want to be findable or have a profile that exposes her.

**Behaviors today**
- 95% consumer. Scrolls, rarely comments. Values strong privacy (the "no usernames / no logs" ideas appeal to her).

**Day in the life**
> On the bus home Priya opens Soapstone, sees a cluster of stones near campus, and listens to four in a row — a poem, someone venting about an exam, a busker's clip. She never drops one, but it's the warmest part of her commute. Three weeks later, feeling brave, she leaves her first anonymous 8-second stone outside the library.

**Design implications**
- **Listening must be effortless and rewarding from minute one** — auto-play, easy skip/next (the "driving mode swipe" idea), a never-empty-feeling map.
- The **cold-start / empty-map problem is existential for her** — she churns instantly from a ghost town. Seeding strategy is critical.
- **Strong, default anonymity & privacy** lowers her bar to eventually contribute.
- She is the **silent majority** — most users will look like Priya, so retention metrics hinge on the *listening* experience, not just creation.

---

## Persona 4 — Greg, "The Completionist" (secondary / tertiary)

> *"There's a badge for that? Say less."*

**Photo:** Early-40s man, fitness watch, mid-jog, glancing at his phone.

- **Age / context:** 42, suburban-edge, drives more than walks, runs for exercise.
- **Occupation:** IT manager.
- **Tech comfort:** High. Pokémon GO raid veteran, Foursquare mayor, Strava segment hunter.

**Goals**
- *Functional:* Collect, complete, rank up. Convert the map into a board to clear.
- *Emotional:* Mastery, streaks, the dopamine of progress.
- *Social:* Leaderboards and bragging rights.

**Frustrations**
- Loses interest fast if there's no progression system or goals.
- Sparse rural/suburban density means few dots to hit — geography fights him.

**Behaviors today**
- Drives the gacha / badge / streak / "tours" / quests ideas in the roadmap.

**Day in the life**
> Greg plans his run to pass three uncollected stone clusters, completing a "First Discovery" bonus in a new neighborhood and extending his 14-day streak.

**Design implications**
- Validates the **gamification roadmap** (gacha, badges, streaks, quests, first-discovery bonus) — but as a **retention layer, not the core**.
- **Risk:** designing primarily for Greg could turn an intimate, ambient app into a grindy points game and alienate Maya/Priya. Keep gamification *optional and secondary*.
- His suburban/low-density problem reframes a real constraint: **the app is strongest in dense, walkable areas.**

---

## Prioritization

| Priority | Persona | Rationale |
|---|---|---|
| **Primary ⭐** | **Maya, The Wanderer** | The core mechanic is built for her mindset; she seeds content and tolerates the cold start. Design must satisfy her first. |
| Secondary | **Priya, The Listener** | Represents the silent majority and the make-or-break listening/retention experience. |
| Secondary | **Darnell, The Tipper** | The utility engine that gives the app durable value and feeds gamification. |
| Tertiary | **Greg, The Completionist** | Validates the retention/gamification layer; must not be allowed to define the core. |

**The central design tension:** Maya/Priya want *ambient, anonymous, intimate*. Darnell/Greg want *recognition, utility, progression*. The roadmap's **Layers/Tags** and *optional* gamification are the proposed reconciliation — validate this early.

---

## Research Gaps (close these to upgrade proto-personas → validated personas)

1. **Zero primary research.** No interviews, surveys, or diary studies exist. Everything above is hypothesis.
2. **Cold-start tolerance is unmeasured** — how empty a map will Priya/Maya tolerate before churning? Existential and untested.
3. **Anonymity vs. attribution** is an open product question (DESIGN.md Q8) *and* an unvalidated persona assumption — it splits Maya/Priya from Darnell/Greg.
4. **Density dependence** — do these personas exist / behave the same in suburban vs. dense-urban geographies?
5. **Privacy concerns of recording in public** — none of the personas' real-world hesitations (being overheard, safety, surveillance) are researched.
6. **Real demographics & motivations** — ages, occupations, and "jobs to be done" are placeholders.

**Recommended next step:** Run `/interview` to script 5–8 discovery interviews targeting Maya- and Priya-type users (walkable-city, lurk-first), and a diary study to measure cold-start tolerance.
