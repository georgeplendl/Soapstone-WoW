# Soapstone — Discovery Research Summary

**Date:** 2026-06-06
**Cycle:** `/design-research:discover` (personas → empathy map → journey map → synthesis)
**Status:** ⚠️ **Provisional.** Grounded in product docs and analogous products, **not** primary research. Everything here is a hypothesis to validate.

**Artifacts produced:**
- `01-Personas.md` — 4 proto-personas
- `02-Empathy-Map-Maya.md` — empathy map for the primary persona
- `03-Journey-Map-Maya.md` — first-week journey for the primary persona

---

## The product in one line
Soapstone lets people drop short voice recordings pinned to a physical spot; you can only hear a stone when you're within 1 mile of where it was left. Ambient, anonymous-feeling, rooted in place — *Dark Souls* messages for the real world.

---

## Who we're designing for

| Persona | One-liner | Axis | Priority |
|---|---|---|---|
| **Maya — The Wanderer** ⭐ | "I want the city to whisper back." | Expression · serendipity · seeds content | **Primary** |
| **Priya — The Listener** | "I just like hearing someone else was here." | Lurk-first · the silent majority · retention | Secondary |
| **Darnell — The Tipper** | "Let me tell you the off-menu order." | Utility · hyperlocal value · recognition | Secondary |
| **Greg — The Completionist** | "There's a badge for that?" | Gamification · progression · retention layer | Tertiary |

**Primary = Maya** because the core mechanic was designed for her mindset and she's the early adopter who seeds content and tolerates an empty map. Satisfy her first.

---

## The 5 key insights

### 1. The cold-start empty map is the existential risk — and it's mis-sequenced. 🔴
The proximity gate means a user **cannot** summon content by panning; if her immediate mile is empty, the map is dead — and this hits *immediately after* the heaviest friction (full sign-up). Priya (the silent majority) churns from a ghost town instantly.
**→ Seeding launch geographies is priority zero**, plus show **ambient density at distance** (heatmaps, city counts, "nearest stone this way") so the map is never visibly dead.

### 2. The proximity-gate friction is the magic, not a cost. 🟢
Walking into range to unlock a stranger's voice IS the product's delight (Journey Stage 4, the #1 advocacy-creating moment). Don't optimize it away in the name of "ease."
**→ Invest in the GPS radar / lock→unlock celebration** (already started — recent radar commit). Apply gate hysteresis so it doesn't flicker.

### 3. There's a core identity tension that splits the personas. ⚖️
Maya/Priya want **ambient, anonymous, intimate**; Darnell/Greg want **recognition, utility, progression**. This maps directly onto the open product question (DESIGN.md Q8: anonymous vs. attributed).
**→ Default to strong anonymity** for the core loop; make **gamification and reputation optional and secondary**; validate **Layers/Tags** as the mechanism that lets both coexist. Don't let Greg's grind redefine an intimate app.

### 4. Sign-up friction blocks curiosity-driven installs. 🟠
An ambient, curiosity-led app forces email + 6-digit code + username/password + a hard location dependency *before* showing any value. Maya's patience erodes; Priya may never commit an account to a thing she hasn't seen.
**→ Offer a "look around first" guest preview** of the map before account creation; defer heavier sign-up steps.

### 5. Recording aloud in public is a real, unaddressed barrier. 🟠
The create loop asks users to talk out loud to their phone in public and trust their identity is protected (Journey Stage 5, the emotional dip). This blocks conversion from listener → contributor.
**→ Reassure on privacy/anonymity at the moment of recording**; make the drop discreet, quick, and celebrated (the Dark Souls "message left" ritual).

---

## Prioritized design implications (impact × feasibility)

| # | Implication | Impact | Feasibility |
|---|---|---|---|
| 1 | **Cold-start seeding + ambient density display** | 🔴 Critical | 🟡 Medium |
| 2 | **Guest preview before sign-up** | 🔴 High | 🟢 High |
| 3 | **GPS radar + lock→unlock magic moment** | 🔴 High | 🟡 Medium |
| 4 | **Strong default anonymity; optional gamification; validate Layers/Tags** | 🟠 High | 🟡 Medium |
| 5 | **Privacy reassurance at record time** | 🟠 Med-High | 🟢 High |
| 6 | **Gentle, geofenced, low-frequency re-engagement (no spam)** | 🟠 Medium | 🟢 High |

---

## How this informs the open questions in DESIGN.md
- **Q4 (auto-play on pane open):** Research leans **yes** — supports Priya's effortless listening and Maya's magic moment.
- **Q8 (anonymous vs. attributed):** Lean **anonymous by default** for the core loop (serves the primary + silent-majority personas); attribution/recognition becomes an *opt-in* layer for Darnell/Greg.
- **Skippable onboarding / guest access:** Research strongly supports a **lurk-before-signup** path — the heaviest friction valley in the journey.
- **Gamification roadmap (gacha, badges, streaks, quests):** Validated as a **retention layer for Greg/Darnell**, but must stay **optional and secondary** to avoid alienating Maya/Priya.

---

## Research gaps — biggest unknowns to close next
1. **Zero primary research** — all of this is hypothesis.
2. **Cold-start churn threshold** — how empty a map before users quit? Existential and unmeasured.
3. **Magnitude of the public-recording barrier.**
4. **Anonymity expectation** — zero identity vs. a pseudonym with thin reputation.
5. **Density dependence** — do these personas behave the same in suburban vs. dense-urban areas?
6. **Notification tolerance** before the app "feels like the others."

---

## Recommended next steps
- **`/interview`** — script 5–8 discovery interviews targeting Maya- and Priya-type users (walkable-city, lurk-first) to validate the personas, the public-recording barrier, and anonymity expectations.
- **`/test-plan`** — design usability tests for the two moments of truth: the **cold-start first open** and the **first walk-to-unlock listen**.
- **Diary study** — measure real cold-start tolerance and ritual cadence over a week in a seeded vs. unseeded neighborhood.
