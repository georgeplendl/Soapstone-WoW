# Journey Map — Maya, "The Wanderer"

**Date:** 2026-06-06
**Persona:** Maya, The Wanderer (primary — see `01-Personas.md`)
**Scenario:** Maya hears about Soapstone, installs it, and tries to reach her first "magic moment" (hearing + dropping a stone) over her first week in a dense, walkable city.
**Boundaries:** From *first awareness* → *advocacy*. Current-state assumptions for an early build per DESIGN.md / App Specification.
**Status:** Provisional — emotional ratings & friction are hypotheses to validate.

---

## Emotional curve (─5 worst … +5 best)

```
 +5│                                  ●Listen
 +4│        ●Aware                    /\         ●Ritual
 +3│       /    \                    /  \       /        \   ●Advocacy
 +2│      /      \      ●Open       /    \     /          \ /
 +1│     /        \    /│\         /      \   /            ●
  0│────/──────────\──/─│─\───────/────────\─/─────────────────
 -1│   /            \/  │  \     /          ●Drop(record)
 -2│  /             Sign│   \   /            (public-recording dip)
 -3│ ●                  │    \ /
 -4│                Permissions  ●Cold-start empty map  ← MoT #1
 -5│
    └ Aware  Sign-up  Open   ColdStart  Listen  Drop   Ritual  Advocacy
```

The journey has **two deep valleys** (permissions/sign-up friction and the cold-start empty map) and **two peaks** (first unlocked listen, established ritual). The single most dangerous dip is the **cold-start empty map** — and it lands *immediately after* the costly sign-up, the worst possible sequencing.

---

## Stage-by-stage

### 1. Awareness  😊 (+4)
- **Goal:** Decide if this is worth installing.
- **Actions:** Sees a friend's post / TikTok / sticker about "the Dark Souls voice-note app." Reads the one-liner: *"Leave a voice message in the real world. Only people nearby can hear it."*
- **Touchpoints:** Word of mouth, social clip, App Store listing.
- **Thinks:** *"That's such a vibe. Is anyone near me using it?"*
- **Feels:** Intrigued, hopeful.
- **Pain points:** The value depends entirely on local density she can't see before installing.
- **Opportunity:** App Store / landing page should show **local activity proof** ("X stones near you") or seed-city framing so she trusts there's something to find.

### 2. Onboarding carousel + Sign-up  😬 (+1 → -2)
- **Goal:** Get in fast and see the map.
- **Actions:** Swipes 5 onboarding slides → email → 6-digit code → location permission → notification permission → username/password (5 steps).
- **Touchpoints:** Onboarding carousel, sign-up flow, OS permission dialogs.
- **Thinks:** *"Okay, okay… can I just SEE it already?"*
- **Feels:** Patience eroding; mild friction fatigue.
- **Pain points:**
  - **No way to preview/lurk before committing an account** — high bar for a curiosity-driven install.
  - Email + 6-digit verification + username/password is heavy for an ambient app.
  - **Location permission is a hard dependency** — denial = dead app.
- **Opportunities:**
  - Allow a **"look around first" guest/preview** of the map before forcing sign-up (huge for Priya/Maya).
  - Consider deferring username/password; lead with the experience.
  - Frame the location ask in the app's voice (the spec's "step outside the gate and they vanish" copy is good).

### 3. First open — **COLD START**  😞 (-4)  ⚠️ MOMENT OF TRUTH #1
- **Goal:** See dots. Find something to listen to.
- **Actions:** Lands on the map. Looks for nearby stones.
- **Touchpoints:** Home map, nearby list, empty state.
- **Thinks:** *"…is that it? There's nothing here. Ghost town."*
- **Feels:** Deflated, let down — the gap between the promise and the empty map.
- **Pain points:** **THE make-or-break risk.** In an unseeded area the map is empty and the proximity gate means she *cannot* summon content by panning. The current empty state ("No stones nearby yet. Drop one?") asks a brand-new user to perform for an empty room.
- **Opportunities (priority zero):**
  - **Seed every launch geography** before inviting users there (operational, not just UX).
  - **Show ambient density at distance** — heatmap when zoomed out, "1,240 stones in your city," nearest-stone direction & distance — so the map never feels dead even when her immediate mile is sparse.
  - Reframe the empty state from "drop one (alone)" to "**here's the nearest stone — 0.8 mi this way**," giving her a quest instead of a void.

### 4. First listen — walk into range  😄 (+5)  ⚠️ MOMENT OF TRUTH #2
- **Goal:** Unlock and hear a real stone.
- **Actions:** Sees a locked dot, uses the GPS radar to navigate toward it, crosses into the 1-mile gate, the pin unlocks, pane auto-plays a stranger's voice.
- **Touchpoints:** Map pins (locked→unlocked), GPS radar, floating listening pane, waveform.
- **Thinks:** *"Oh my god, it actually works. Someone stood right here."*
- **Feels:** Delight, wonder — **the core magic moment.** This is what she'll tell friends about.
- **Pain points:** If navigation to the dot is confusing, or the unlock transition isn't satisfying, the payoff fizzles. GPS edge-flicker at the gate could re-lock and frustrate.
- **Opportunities:**
  - Make the **lock→unlock transition a celebrated moment** (haptic + audio + visual "the gate opens").
  - Invest in the **GPS radar / warmer-colder navigation** — this is the heart of the experience.
  - Apply the planned **hysteresis buffer** so the gate doesn't flicker at the edge.

### 5. First drop — record in public  😐→🙂 (-1 → +2)  (the public-recording dip)
- **Goal:** Leave her own stone.
- **Actions:** Tap-and-hold FAB, mic permission prompt (first time), records ~12s, reviews, drops on the spot.
- **Touchpoints:** FAB, mic permission, recording UI, review screen, drop confirmation.
- **Thinks:** *"People are around… do I look weird talking to my phone? Who hears this? Can they find me?"*
- **Feels:** Self-conscious, exposed → then quietly proud once it's dropped.
- **Pain points:**
  - **Recording aloud in public is socially exposing** — a real barrier to the create loop.
  - **Identity/privacy fear** — "does my voice or username reveal me?"
  - Mic permission denial would soft-block the whole loop.
- **Opportunities:**
  - Reassure on privacy at the moment of recording (anonymity affordance, who-can-hear-this clarity).
  - Make the drop feel **discreet and quick**; consider a "your voice is anonymous" micro-confirmation.
  - Celebrate the drop (the Dark Souls "message left" ritual) to convert exposure → pride.

### 6. Re-engagement / ritual  🙂 (+3)
- **Goal:** Make Soapstone part of her walks.
- **Actions:** Opens it at the start of walks; gets a gentle "3 new stones near you" nudge; replies to others.
- **Touchpoints:** Notifications, home map, nearby list.
- **Thinks:** *"Let me check what's around before I head out."*
- **Feels:** Comfortable, habitual, mildly delighted by recurring serendipity.
- **Pain points:**
  - **Notification spam would break the spell** and feel like every other app.
  - Without *fresh* nearby content, the ritual decays (density dependence again).
- **Opportunities:**
  - **Gentle, geofenced, low-frequency nudges** ("new stones where you're heading"), never engagement-bait.
  - Frame any streak/capsule mechanic as **ritual, not grind** (see Daily Streak Capsules idea).

### 7. Advocacy  😊 (+3)
- **Goal:** Share the magic; pull friends in.
- **Actions:** Tells friends about "the voice-note app," shares a stone, posts a clip.
- **Touchpoints:** Share action (3-dot menu), word of mouth, social.
- **Thinks:** *"You have to try this — but go to a busy area."*
- **Feels:** Enthusiastic evangelist — *if* her first week delivered the magic moment.
- **Pain points:** She instinctively warns friends about empty areas — advocacy is **gated on having survived the cold start herself.** Sharing a *locked* stone a friend can't hear (different city) could confuse/disappoint.
- **Opportunities:**
  - Make **sharing carry a taste** of the stone + a "find more near you" hook that respects the proximity model.
  - **Referral that helps seed density** in her circle's shared neighborhoods (friends-seed-friends solves cold start socially).

---

## Moments of truth
1. **The cold-start first open (Stage 3)** — empty map immediately after costly sign-up. The #1 churn risk. *Win here or nothing else matters.*
2. **The first unlocked listen (Stage 4)** — the magic moment that creates advocates. *The entire product promise is validated or broken here.*
3. **The first public drop (Stage 5)** — converts a consumer into a contributor; gated by privacy reassurance and social self-consciousness.

## Top opportunities (impact × feasibility)

| Rank | Opportunity | Impact | Feasibility | Notes |
|---|---|---|---|---|
| 1 | **Cold-start seeding + ambient density display** (heatmap, "nearest stone this way," city counts) | 🔴 Critical | 🟡 Medium | Mix of ops (seeding) + UX. Without it, funnel dies at Stage 3. |
| 2 | **Guest / "look around first" preview before sign-up** | 🔴 High | 🟢 High | Removes the heaviest friction valley; lets curiosity convert. |
| 3 | **Invest in GPS radar / lock→unlock magic moment** | 🔴 High | 🟡 Medium | The core delight; already on the roadmap (recent radar commit). |
| 4 | **Privacy reassurance at the moment of recording** | 🟠 Med-High | 🟢 High | Unblocks the create loop; cheap to add. |
| 5 | **Gentle geofenced re-engagement (no spam)** | 🟠 Medium | 🟢 High | Drives the ritual that retains Maya. |

---

## Gaps to validate
- Real cold-start churn threshold (Stage 3) — the central unknown.
- Whether a guest-preview meaningfully lifts conversion vs. diluting account creation.
- Magnitude of the public-recording barrier (Stage 5).
- Notification frequency tolerance before the app "feels like the others" (Stage 6).
- Cross-geography sharing confusion in advocacy (Stage 7).
