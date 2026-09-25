# Empathy Map — Maya, "The Wanderer" (Primary Persona)

**Date:** 2026-06-06
**For:** Primary persona (see `01-Personas.md`)
**Status:** Provisional — quotes are *plausible/illustrative*, not from real interviews. Validate via `/interview`.

> ⚠️ The "Says" quotes below are **synthesized**, written in Maya's voice to make the map usable, but they are hypotheses. Replace with verbatim quotes after discovery interviews.

---

```
┌──────────────────────────────────────┬──────────────────────────────────────┐
│  SAYS                                 │  THINKS                              │
│  (synthesized quotes)                 │  (inferred beliefs)                  │
├──────────────────────────────────────┼──────────────────────────────────────┤
│ "I want the city to whisper back."    │ "Is anyone actually near me right    │
│ "It's like finding graffiti, but you  │  now, or is this a ghost town?"      │
│  can HEAR it."                         │ "I don't want to perform — I just    │
│ "I'll detour two blocks for a good    │  want to leave a trace."             │
│  one."                                 │ "Will my voice expose who I am?"     │
│ "I don't want another feed."           │ "The walk-to-unlock thing is the     │
│ "Who else has stood right here?"       │  whole point — don't make it easy."  │
│                                        │ "If it's dead in a week, I'm out."   │
├──────────────────────────────────────┼──────────────────────────────────────┤
│  DOES                                 │  FEELS                               │
│  (observable behaviors)               │  (emotional states)                  │
├──────────────────────────────────────┼──────────────────────────────────────┤
│ Walks everywhere, one earbud in.      │ CURIOUS — pulled toward unknown dots │
│ Opens the app at the start of a walk. │ DELIGHTED by serendipitous finds     │
│ Detours toward pulsing/locked dots.   │ SAFE in low-stakes anonymity         │
│ Reads plaques, stickers, graffiti.    │ ANXIOUS about being identified/      │
│ Uses Strava, BeReal, Letterboxd       │   overheard recording in public      │
│  (ritual + community apps).            │ IMPATIENT / let-down by empty maps   │
│ Drops short replies, rarely long      │ PROUD, quietly, of leaving a mark    │
│  monologues. No follower-chasing.      │ FATIGUED by performative social apps │
└──────────────────────────────────────┴──────────────────────────────────────┘
```

---

## Goals (what Maya is trying to achieve)
- **Discover the hidden texture of places she already moves through.**
- Experience **serendipity** — the unplanned, human surprise.
- Feel **connected to strangers without the performance** of identity-based social media.
- **Leave a trace** — a small, ephemeral mark on a place that mattered.
- Maintain a lightweight, low-pressure **ritual** (like opening BeReal or logging a Strava walk).

## Pain Points (barriers & frustrations)
- **Cold start / empty map** — the single biggest churn risk. Nothing nearby = instant abandonment.
- **Performance anxiety** — fear that her voice or posts expose her identity or invite judgment.
- **Recording in public is awkward** — talking aloud to a phone on a street feels exposing/unsafe.
- **Permission fatigue & friction** — location + mic asks could stall her before she feels value.
- **Disorientation** — if she can't tell where the dots are or how to navigate to them, the magic dies.
- **Social-media fatigue** — if Soapstone starts feeling like another feed/leaderboard, she leaves.

---

## Key Insights → Design Implications

| Insight | Design implication |
|---|---|
| The **empty map kills her first** | Cold-start seeding is *priority zero*. Show ambient density even when sparse (heatmaps when zoomed out, "stones in your city" framing). Never present a blank, dead map at first open. |
| **Walk-to-unlock is the magic, not a cost** | Invest in the GPS radar / navigation toward locked dots. The friction is the feature — make *finding* feel like a quest, not a chore. |
| **She fears exposure** (identity + recording in public) | Default to **strong anonymity** (random usernames). Make recording feel private/discreet; consider visual cues that reassure her about what's shared. Address the "recording aloud in public" hesitation explicitly. |
| **She's allergic to performance** | **No likes/followers in her core loop.** Keep gamification optional and out of her face. Resist turning the home screen into a feed. |
| **Ritual drives retention** | Lightweight re-engagement (a daily "what's near you" nudge) without notification spam. The streak/capsule idea could serve her *if* framed as gentle ritual, not grind. |
| **She'll tolerate friction for payoff** | The intentional tap-and-hold drop and the 1-mile gate are *aligned* with her — don't over-optimize them away for "ease." |

---

## Gaps (what we still need to learn about Maya)
1. **Real quotes** — all "Says" are synthesized. Run interviews.
2. **Cold-start threshold** — exactly how empty before she churns? Untested and existential.
3. **Public-recording hesitation** — how big a barrier is talking aloud in public? Could block the entire create loop.
4. **Anonymity expectations** — does she *want* zero identity, or a pseudonym she can build a thin reputation under?
5. **Navigation expectations** — does she expect turn-by-turn to a dot, or just a radar/"warmer-colder" feel?
6. **Ritual cadence** — daily? Only on long walks? Determines notification & streak design.

**Next:** journey map for Maya's first-week experience (see `03-Journey-Map-Maya.md`), where the cold-start and public-recording pains will concentrate at specific stages.
