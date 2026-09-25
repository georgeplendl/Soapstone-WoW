# Discovery Plan: Soapstone — Build/Kill

**Date:** 2026-06-06
**Cycle:** `/pm-product-discovery:discover`
**Product stage:** New product (concept without validated demand)
**Decision this informs:** **Build / Kill** — is Soapstone worth building at all?
**Status:** ⚠️ Provisional. Built on existing product docs + research (`docs/Research/`), which are themselves hypotheses. No primary validation yet — that's what this plan exists to get.

---

## Discovery question

> Which beliefs must be true for Soapstone to be worth building — and how do we test the riskiest ones cheaply, *before* writing the app?

Soapstone is unusually well-specified for a new product (personas, JTBD, journey map, scoped MVP, resolved decisions). So discovery here is **not** "what to build" — it's de-risking the leap-of-faith assumptions that determine whether the core mechanic (voice + 1-mile proximity gate) actually works on real humans.

---

## Ideas explored (divergent phase)

Same core mechanic, distinct *shapes* the product could take:

**Three competing concept bets (different incumbents to beat):**
1. **Ambient "the city whispers back"** — anonymous, expressive, atmosphere-first. *Beats: graffiti + doing nothing.* (current MVP)
2. **Hyperlocal voice tips** — "off-menu order," voice Yelp pinned to a spot. *Beats: Google reviews.*
3. **Place-based collection game** — human voice as the Pokémon-GO collectible. *Beats: Pokémon GO / Foursquare.*

**Enablers any bet needs:**
4. Guest-preview-first (lurk before signup)
5. The unlock ritual as the product (invest in walk→radar→unlock)
6. Ambient density display (heatmaps / "nearest stone this way")
7. Seeded-neighborhood concierge launch (40 curated stones)
8. Onboarding-stones-as-tutorial (in MVP)
9. Whispers (directional audio cue)
10. Layers/Tags as the coexistence engine (lets the 3 jobs share one app)
11. Reply/thread stones (reciprocity)
12. SMS-drop (zero-install seeding)
13. **Asymmetric gating (read-anywhere, write-here)** — remove the *listen* gate (pan/zoom + hear any stone worldwide) while keeping the *post* gate, with drops anchored to a geolocated area or Google POI. ⚠️ *Provisionally judged a likely bad idea — see below.*

### On #13 — asymmetric gating (lean: against)

This surfaced as a candidate answer to the cold-start ⟷ gate tension: if listening is global, the first user in any area never sees an empty map. Real upside, but it is a **pivot, not a tweak** — it pulls Soapstone away from bet #1 ("the city whispers back") toward bet #2 (utility) and a new "browse the world through voice" shape.

**Why it's probably the wrong trade:**
- **Proximity *was* the relevance algorithm.** "This happened where I'm standing" is what makes an anonymous stranger's clip worth caring about. Global listening keeps the content but strips the specialness — a stone three time zones away has no claim on attention, so we'd owe a new curation mechanism (topics/following/trending) we don't have.
- **It deletes the variable instead of testing it.** V2 ("worth physically *walking* to") is a leap-of-faith assumption. Removing the listen-gate doesn't answer V2 — it sidesteps it before the pilot can.
- **Supply risk.** Global browsing may convert active droppers into passive consumers, starving the very supply side (U2/C) the loop depends on.

**Worth keeping regardless of the gate decision:** anchoring *posts* to a Google POI / business / landmark (vs. raw GPS). It sharpens the utility job and gives a natural seeding handle. Decoupled from the listen-gate question.

**If we ever revisit it, go tiered, not binary:** discover globally (see the map is alive / 3-sec teaser / heatmap), but require presence to fully unlock and reply — keeping the walk as the payoff rather than removing it.

## Selected for validation

**All three jobs + enablers** carried forward. Rationale: a build/kill needs the widest coverage. The core mechanic is tested primarily through the ambient bet (#1, the MVP), but assumptions are surfaced across utility (#2) and collection (#3) so we learn *which job dominates* — and the enablers (#4–#10) are where execution risk lives.

---

## Critical assumptions

| # | Assumption | Category | Impact | Uncertainty | Priority |
|---|-----------|----------|--------|-------------|----------|
| G1 | Cold-start density is solvable per-neighborhood (~30–50 seeded stones make a mile feel alive) | Go-to-Market | 🔴 Existential | 🔴 High | **1 (leap)** |
| V1 | People genuinely desire "exchange a human trace with strangers in a place" — enough to open an app | Value | 🔴 High | 🔴 High | **2 (leap)** |
| V2 | A stranger's anonymous 30-sec clip is worth physically walking to | Value | 🔴 High | 🔴 High | **2 (leap)** |
| U2 | People will record their voice aloud in public to a stranger-facing app | Usability | 🔴 High | 🔴 High | **3 (leap)** |
| U3 | The walk→radar→unlock moment feels *magical*, not confusing/frustrating | Usability | 🔴 High | 🟡 Med | 4 |
| V3 | Listeners (silent majority) retain just from hearing others were here | Value | 🟠 High | 🟡 Med | 5 |
| U1 | Two onboarding stones teach the gate without coach-marks | Usability | 🟠 Med | 🟡 Med | 6 |
| U4 | Guest-preview-first converts curiosity better than gated signup | Usability | 🟠 Med | 🟡 Med | 6 |
| B1 | Monetization exists that doesn't poison anonymity/ambient feel | Viability | 🟠 High | 🔴 High | Defer |
| B2 | Indefinite-TTL storage costs stay viable | Viability | 🟡 Med | 🟢 Low | Defer |
| F1 | GPS/geofence reliable enough the gate doesn't flicker/mislocate | Feasibility | 🔴 High | 🟢 Low | Monitor |
| F2 | Background geofence notifications work within OS battery limits | Feasibility | 🟠 Med | 🟡 Med | Monitor |
| F3 | Voice moderation/abuse tractable for a small team | Feasibility | 🟠 Med | 🟡 Med | Monitor |
| G2 | Grows cluster-by-cluster without dying in the gaps | Go-to-Market | 🟠 High | 🔴 High | Defer |

**Two structural tensions:**
- **Anonymity ⟷ monetization** — what makes it safe to post (no identity, no logs) makes it hard to monetize via ads/attribution. (V/B)
- **Cold-start ⟷ proximity-gate** — the gate that creates the magic guarantees an empty map for the first user in any area. (V/G)

**The leap-of-faith set (G1, V1, V2, U2, U3) is testable together in one field pilot.**

---

## Validation experiments

| # | Tests | Method | Success criteria | Effort | Cost |
|---|-------|--------|------------------|--------|------|
| A | V1 | Landing page + explainer video, paid traffic | ≥8% visit→email | ~3 days | ~$100 |
| B | V2, U3 | Wizard-of-Oz concierge walk (no app) | ≥60% choose to walk; ≥50% "delightful" | ~1 wk | ~$0 |
| C | U2 | Record-in-public probe (folded into B) | ≥40% listener→dropper | none extra | $0 |
| D | **G1 + whole loop** | **Field pilot: 40 seeded stones, 25–40 locals, 2 wks** | ≥30% return; ≥20% organic drop; ≥70% "felt alive" | 2–3 wks | ~$200 |
| E | B1 | Pricing/concept probe (supporter tier vs. sponsored stones) | run only if D passes | later | — |

### Experiment details

**A — Demand smoke test.** Landing page, one 60-sec "the city whispers back" explainer, single CTA: "Notify me when Soapstone comes to my neighborhood." ~500 visitors via r/Sacramento, walkable-city + onebag communities, local Discords. *≥8% email = real latent desire → proceed. <3% = ambient job may not exist → investigate/kill.*

**B — Worth-the-walk concierge (Wizard-of-Oz).** No app. Hidden voice notes (SoundCloud/WhatsApp) + manual "you're getting warmer" texts, or a no-code geofence (Radar.io) + simple web audio page. Hand-place 3 stones ~0.4mi out. Walk 10 recruited testers. Measure % who choose to detour, delight rating, "would you do this unprompted?" *Validates friction-as-magic before building the radar.*

**C — Record-in-public probe.** At the end of B, invite each tester to leave their own stone in public. Observe hesitation; debrief on what would make it feel safe. *<25% drop = supply side broken = major kill signal.*

**D — The Field Pilot (the build/kill gate).** Wizard-of-Oz or thin no-code rig (shared map + audio links + manual notifications). Seed 40 *good* stones across one ~1-mile Citrus Heights cluster (landmarks, parks, corners). Recruit 25–40 locals (coffee-shop flyers, local FB groups, the Exp-A list). Run 2 weeks. Measure: day-1 "feels alive?" survey, session-2 return rate, organic drops, unlock-notification→open conversion, churn-on-empty.

> **Optional two-arm tweak (tests idea #13 cheaply):** run a second cohort with the *listen-gate removed* (global pan/zoom listening) against the gated cohort. Compare organic-drop rate and "felt special" between arms. Hypothesis (lean: against #13) — the ungated arm shows **higher reach but lower drops and lower specialness**, confirming proximity is load-bearing. Only add this arm if recruitment supports two cohorts; otherwise keep #13 as a documented fork, not a build path.

**E — Monetization probe.** Only after D = BUILD. Pricing-sensitivity test of "supporter" tier vs. localized sponsored stones with pilot users.

---

## Discovery timeline

```
Week 1     A  smoke test          gate: ≥8% email?
Week 2     B + C  concierge walk  gate: detour + drop real?
Weeks 3–4  D  field pilot         ←── BUILD / KILL decision
Later      E  monetization        only if D = BUILD
```
Each gate kills cheaply before the next spend.

---

## Decision framework

**Build/kill is decided at Experiment D.**

- ✅ **BUILD** — return ≥30% AND organic drops ≥20% AND "felt alive" ≥70%. The seeded mile sustains itself → build the MVP as scoped in `docs/MVP - Draft.md`.
- 🟡 **ITERATE** — mixed signals:
  - Loved listening, wouldn't post → fix the record-in-public barrier (privacy reassurance, discreet drop) before building.
  - Liked content, didn't return → fix re-engagement / ambient density display.
  - Returned but density felt thin → seeding model needs more stones/curation per mile.
- ❌ **KILL / PIVOT** — a *seeded, curated, hand-held* mile still churns. Cold-start is unsolvable at achievable density and the proximity gate is fatal in its current form. Consider pivoting to a lower-density-tolerant shape (utility/tips bet #2, or relax the gate).

**Early kill gates (before the pilot):**
- Exp A <3% email → ambient desire likely absent.
- Exp B <30% choose to walk → friction-as-magic is a myth.
- Exp C <25% drop → loop can't self-sustain on supply.

---

## Research gaps / biggest unknowns
1. **Zero primary research to date** — this entire plan exists to close that.
2. **Cold-start churn threshold** — how empty before users quit? (Exp D)
3. **Magnitude of the public-recording barrier.** (Exp C)
4. **Which job dominates** — ambient vs. utility vs. collection (determines positioning + which incumbent to attack).
5. **Density dependence** — suburban (Citrus Heights) vs. dense-urban behavior may differ.
6. **Monetization viability under anonymity constraints.** (Exp E)

---

## Next steps
- **`/interview`** — script 5–8 discovery interviews (Maya/Priya-type, walkable-city, lurk-first) to validate hire/fire triggers, the public-recording barrier, and anonymity expectations. Good companion to Exp A.
- **`/test-plan`** — usability test for the two moments of truth (cold-start first open; first walk-to-unlock).
- **`/setup-metrics`** — instrument the field pilot (return rate, drop rate, unlock→open, churn-on-empty).
- **PRD** — only after D = BUILD.
