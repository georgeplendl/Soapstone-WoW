## Soapstone MVP — Draft Scope

The smallest version of Soapstone that still produces a "wow" moment. Strips out all gacha-style gamification (Cairns, capsule pulls, pin skins, streaks, quests, first-discovery rewards) and focuses entirely on the irreducible loop. Those ideas live in `docs/Ideas/` and are deferred until the core loop proves itself.

---

### Guiding principle

The magic is **someone left audio here, and you have to physically be here to hear it.** If that single experience lands, the app works. If it doesn't, no amount of layered mechanics will save it. MVP exists to find out which is true.

---

### The core loop (must ship)

1. **Drop** a stone at your current GPS location (press-and-hold record on the FAB)
2. **See** stones on a map — unlocked pins (within 1-mile gate) and locked pins (outside it)
3. **Listen** to unlocked stones via the floating listening pane

That's the entire game. Three verbs.

---

### In scope for MVP

- **Map home screen** with user location, sonar pulse, 1-mile gate ring, unlocked + locked pins
- **Nearby list** (horizontal pill row) for unlocked stones
- **Recording flow** — press-and-hold FAB, review screen, drop confirmation
- **Listening pane** — unlocked variant (waveform, scrubber, play/pause, restart) and locked variant (lock icon + distance)
- **Sign in with Apple / Google** — no email 2FA flow at launch
- **Anonymous stones by default** — no usernames shown in the listening pane
- **Report + Block** in the listening pane overflow menu (required for app store approval)
- **Microphone, location, and notification permission** flows with soft-block / settings deep-link recovery
- **Two notifications** (see below)
- **Two onboarding stones** placed in every new user's gate on first launch (see below)

---

### First-run experience: Onboarding stones

The first time a user opens the map, two prerecorded stones are placed within their 1-mile gate. Only this user sees them — they are personal to the account and never appear on anyone else's map. Together they replace the traditional coach-mark tutorial: the user learns what Soapstone is by *using* it, not by reading instructions over a dimmed screen.

#### Stone 1 — Welcome

Closer to the user. A friendly hello in the dropper's voice that introduces the gate concept by demonstration. Something like:

> "Hey — welcome to Soapstone. I'm a voice message someone left here for you to find. You can hear me because you're within a mile of this spot. Walk too far and I'll go quiet. That's the whole game."

#### Stone 2 — Drop instruction

Placed further away, ideally near the edge of the gate so the user has to pan or walk a little to reach it. Teaches the drop mechanic:

> "Now you try. Press and hold the button at the bottom of the screen, say something, and let go. That stone stays right where you dropped it for anyone nearby to hear."

#### Why this works

- **Solves the empty-map problem instantly.** No matter where in the world a user opens the app, the map has content from the first second.
- **Replaces the coach-mark tutorial.** Tutorials interrupt; onboarding stones *are* the experience. The user listens to a real piece of audio — the medium of the app — instead of reading instructions about audio over a dimmed screen.
- **Demonstrates the gate by example.** Seeing two unlocked pins inside a 1-mile circle is more legible than any text explanation.
- **Reusable per launch geography.** When Soapstone expands to a new city or neighborhood, the onboarding stones don't need to be re-recorded — they're tied to the user, not the place.
- **Sets the bar for what a good stone sounds like.** The user's first listening experience is curated, well-recorded, and intentional — exactly what we want them to imitate when they drop their first stone.

#### Lifecycle

- Placed pseudo-randomly within the user's 1-mile gate on first map load, but spaced deliberately — Stone 1 at ~0.3 mi, Stone 2 at ~0.8 mi. Random enough to feel organic; constrained enough to ensure they're always meaningfully separated and Stone 2 creates a pull.
- Visible only to that user; never returned by anyone else's nearby query
- Persist until heard, so a user who closes the app before listening still finds them on return
- Once heard, fade from the map — they've served their purpose and shouldn't clutter the experience
- Do not count toward any global listen counts; cannot be reported or blocked
- Fresh install = fresh onboarding stones (don't try to detect reinstalls)
- If the user is moving when the app first opens (e.g., on a train) and the stones drift out of range before being heard — accept the edge case. They're gone. Come back another time. Re-anchoring adds complexity and the scenario is rare enough not to design around.

---

### Notifications at launch

Two notifications. No others.

#### 1. "A stone has unlocked near you."

Fires when the user physically walks into range of a stone they haven't heard yet. This is the moment of discovery and it's the most direct conversion from "phone in pocket" to "open the app." Without this, users only find stones by actively checking the map, which means the app sits unopened most of the time.

- Triggered by geofence crossing, not by polling
- Throttled — if multiple stones unlock at once (e.g., walking into a dense area), batch into one notification ("3 stones unlocked nearby")
- Respects standard quiet hours / Do Not Disturb
- Tapping the notification deep-links to the map, centered on the unlocked pin(s)
- **Opt-in during onboarding**, prompted after the location access ask (natural moment — user has just granted location, unlock notifications are the obvious next permission to request)

#### 2. "Someone heard your stone." *(delayed / batched)*

Closes the loop for the dropper. Right now a dropper has no idea anyone is listening — that's the most likely cause of one-and-done churn. This notification gives the dropper a felt reward without introducing any gamification surface.

- **Batched on a 30-minute check-in interval**, not real-time and not a daily digest. If new listens occurred in the last 30 minutes, send one notification ("X people heard your stones"). No notification if nothing new.
- Why batched: avoids dopamine spam, avoids feeling surveillance-y for the listener, and clusters the joy without making the dropper wait until the next morning
- Tapping the notification deep-links to a simple "Your stones" view showing recent listen activity

---

### Explicitly out of MVP

Cut to keep the surface area small. None of these are bad ideas — they're just not what proves the core loop.

- Activity / Notifications feed tab (the two push notifications above replace it)
- My Stones as a standalone tab — fold into Profile
- Share button in the listening pane overflow
- Stone TTL extension mechanic — stones are indefinite at launch; revisit if storage becomes an issue
- Per-user drop rate limits — add when spam becomes a real problem, not before
- Onboarding carousel of 5 slides — cut to ≤3, or a single animated splash
- Welcome tutorial / coach-marks — replaced entirely by the two onboarding stones (see above)
- Username attribution, profile pages with stats, follower/following relationships
- All gamification: Cairns, capsule pulls, pin skins, daily streaks, quests, first-discovery rewards, leaderboards
- Audio editing / trimming after recording
- Replies to stones, threading, reactions

---

### The cold-start problem

The hardest MVP problem isn't UI — it's an empty map. A first-time user who opens the app and sees nothing will bounce. Fixing this requires:

- **Launch in Sacramento / Citrus Heights / Roseville, CA** — not a city-wide launch, one tight neighborhood cluster. The 1-mile gate is unforgiving in low-density areas.
- **Seed ~30–50 stones** in the launch neighborhood at landmarks, parks, viewpoints, and quiet corners — recorded by the founding team, friends, local artists, anyone willing
- Treat seed content as a **product investment**, not a hack. The first stones a user hears define what they think Soapstone *is*. They should be good.

This is the unsexy work that determines whether the app feels magical or feels broken on day one.

---

### Where joy comes from in MVP

Without gacha rewards, joy has to come from atmosphere and presence:

- The **sonar pulse** on the user dot — keep, it's mood
- A subtle **audio + haptic cue** when a stone enters the gate as you walk (the unlock moment should *feel* like something)
- The **press-and-hold record gesture** should feel weighty — haptics, a slight "drop" animation on release, the sense of leaving something behind
- The **locked pin just out of reach** — the pull to walk over there is the entire game

Atmosphere over mechanics. The constraint of the 1-mile gate is the gameplay.

---

### What gets added back first if MVP works

In rough order of priority, only after the core loop has proven itself:

1. Attributed (non-anonymous) stones, opt-in, with a profile screen
2. **Whispers** — directional audio cue for nearby unlocked stones (deferred from the Ideas folder; on-brand because it uses the medium itself)
3. Lightweight social: reply stones tethered to an original
4. The first piece of gamification — likely **First Discovery** credit (no rewards, just the social attribution line) before any capsule-pull mechanics

Everything else stays in `docs/Ideas/` until there's evidence the app needs more than its core loop.

---

### MVP decisions (resolved)

| # | Question | Decision |
|---|----------|----------|
| 1 | Stone lifespan | **Indefinite** — simplest path for MVP; revisit if storage becomes a concern |
| 2 | Max recording length | **30 seconds** |
| 3 | Launch neighborhood | **Sacramento / Citrus Heights / Roseville, CA** |
| 4 | Locked pins on map | **Yes** — locked pins always visible; the out-of-reach pull is core to the experience |
| 5 | "Someone heard your stone" schedule | **30-minute batched check-in** — fire one notification if any new listens in the last 30 min |
| 6 | Unlock notification opt-in | **Opt-in during onboarding**, prompted immediately after the location access ask |
| 7 | Onboarding stone placement | **Pseudo-random within the gate**, but constrained: Stone 1 ~0.3 mi, Stone 2 ~0.8 mi |
| 8 | FAB gating on onboarding stones | **FAB always active** — the two stones are for discovery, not instruction; don't gate the core action |
| 9 | Moving-user edge case | **Accept it** — if stones drift out of range before heard, they're gone; user can return another time |
