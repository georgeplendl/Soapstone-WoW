# Soapstone — Jobs-to-Be-Done

**Date:** 2026-06-06
**Builds on:** `01-Personas.md`, `00-Research-Summary.md`
**Status:** ⚠️ Provisional — derived from product concept + personas, not primary research. Job statements are hypotheses to validate in `/interview`.

> JTBD reframes the question from *"what features should Soapstone have?"* to *"what job are people hiring it to do, and what are they firing to do it?"* The most useful output below is the **competing alternatives** (what users hire *today*) and the **underserved outcomes** — because Soapstone's real competitor isn't another app, it's graffiti, a text to a friend, a podcast, or doing nothing.

---

## The core job

> **When I'm moving through a place, I want to exchange a small, authentic, human trace with the strangers who share it — so I can feel connected to where I am without the cost and performance of social media.**

Everything else is a variation on this. Note what the core job is *not* about: it is not "post content," not "build an audience," not "navigate." The currency is **presence and place**, not reach.

---

## The three dimensions

### Functional — the practical task
- **Discover** what's worth knowing/feeling about the exact spot I'm standing in.
- **Leave** a short voice trace pinned to a place, with near-zero effort.
- **Find my way** to the human signals nearby (the walk-to-unlock).

### Emotional — the feeling sought / avoided
- **Seek:** wonder, serendipity, low-stakes belonging, the quiet pride of leaving a mark.
- **Avoid:** the exhaustion and exposure of performing for an audience; the loneliness of anonymous public space; FOMO/algorithmic pressure.

### Social — how I want to be perceived
- **Maya/Priya:** perceived by *no one in particular* — anonymous presence, not identity. ("I was here" without "I am ___.")
- **Darnell:** perceived as the **helpful local / tastemaker** — light recognition, not fame.
- **Greg:** perceived as an **accomplished explorer** — badges, streaks, status among peers.

The social dimension is where the personas split hardest — and it's the crux of your open anonymity question.

---

## Job stages (the full lifecycle of one "hire")

Using Ulwick's universal job map, mapped to Soapstone:

| Stage | What the user is doing | Soapstone touchpoint | Biggest underserved gap |
|---|---|---|---|
| **1. Define** | "Is there anything human near me right now?" | Open app, glance at map | Can't tell density before committing (cold start) |
| **2. Locate** | Find the stones worth my attention | Map pins, nearby list, GPS radar | Sparse mile = nothing to locate; no "warmer/colder" pull |
| **3. Prepare** | Decide to detour / walk into range | Locked-pin pane, radar navigation | Friction-as-magic *if* navigation is good; dead end if not |
| **4. Confirm** | "Is this worth the walk?" | Distance, age, count metadata | Can't preview a locked stone — pure gamble on the detour |
| **5. Execute** | Listen / record + drop | Listening pane; tap-and-hold FAB | Recording aloud in public; "who hears this?" anxiety |
| **6. Monitor** | "Did anyone hear mine?" | Play counts, activity feed | Validation loop thin/undefined (esp. for Darnell) |
| **7. Modify** | Reply, react, leave another | Reply drop, reactions (roadmap) | Conversation/threading not yet a first-class loop |
| **8. Conclude** | Walk away feeling it was worth it | Re-engagement nudge, ritual | Ritual decays without fresh nearby content |

**The job breaks most often at stages 1–2 (cold start) and 5 (public-recording barrier)** — the same failure points the journey map flagged.

---

## Outcome expectations (how users measure success)

Phrased as Ulwick "outcome statements" — *direction + metric + object* — usable later for opportunity scoring:

**Functional**
- Minimize the *time* to find something worth listening to nearby.
- Minimize the *effort* to drop a stone (sub-15-second create loop).
- Increase the *likelihood* that a detour pays off with a good stone.

**Emotional**
- Increase the *frequency* of genuine surprise/delight per session.
- Minimize the *anxiety* of being identified or judged when posting.
- Increase the *sense* that "I'm not alone in this place."

**Social**
- (Darnell) Increase the *number* of people who benefit from my local knowledge.
- (Greg) Increase the *visibility* of my exploration accomplishments.
- (Maya/Priya) Minimize the *exposure* of my identity while still leaving a trace.

---

## Competing alternatives — what users "hire" today

This is the most decision-relevant section: Soapstone must beat these on the job, not on features.

| When the user wants to… | They currently hire… | Why it underserves the job | Soapstone's wedge |
|---|---|---|---|
| Feel connected to a place | Graffiti, stickers, plaques, just observing | Static, anonymous-but-mute, no reciprocity | A place can "talk back" in a human voice |
| Leave a local tip | Google/Yelp review, text a friend | Global + permanent + sterile text; or 1:1 only | Hyperlocal, in-the-moment, voice carries nuance |
| Ambient company on a commute | Podcasts, music, TikTok | Global, algorithmic, not *here* | Tied to *this* place and the strangers in it |
| Express a fleeting feeling | Tweet, BeReal, Close Friends story | Tied to identity, performative, permanent | Ephemeral, anonymous-feeling, no audience pressure |
| Explore / collect places | Pokémon GO, Foursquare/Swarm, Strava | Game-y but not *expressive/human* | Human voice as the collectible, not points |
| Do nothing | (the status quo) | Loneliness of anonymous public space persists | Low-effort serendipity worth opening the app for |

**Key strategic read:** Soapstone's hardest competitor for the *primary* persona is **graffiti + doing nothing** (the ambient/expressive job), while for Darnell it's **Google reviews** (the utility job) and for Greg it's **Pokémon GO** (the collection job). One app, three different incumbents to beat — another argument for **Layers/Tags** so each job has a clean lane.

---

## Underserved opportunities (where today's solutions fail the job)

1. **"Is anyone human near me *right now*?"** — No existing product answers this for a specific spot. **Highest-value, most-underserved outcome** — but only deliverable if density exists (cold start again).
2. **Voice as the medium for hyperlocal tips** — Google reviews are text and global; voice + proximity is genuinely novel for Darnell's job.
3. **Expression without an audience** — Every social app couples expression to identity/reach. The job "leave a trace without performing" is structurally underserved; Soapstone's anonymity model is the wedge.
4. **"Was my trace worth leaving?"** (Stage 6 monitor) — thinly served today; play counts/reactions close the loop, especially for contributors.
5. **Reciprocity with strangers in shared space** — the reply/thread loop (Stage 7) is the deepest version of the core job and barely exists anywhere.

---

## Design implications

| JTBD finding | Implication for Soapstone |
|---|---|
| Core job currency is **presence + place**, not reach | Keep the loop about *here and now*; resist feed/follower mechanics that re-introduce performance. |
| Job breaks at **Stage 1–2 (cold start)** | Density/seeding is the precondition for *any* job getting done — priority zero (consistent with journey map). |
| Job breaks at **Stage 5 (public recording)** | Privacy reassurance + discreet, sub-15s create loop directly serves the functional + emotional outcomes. |
| **Confirm stage is a blind gamble** (Stage 4) | Give a low-cost signal of whether a detour is worth it (age, popularity, maybe a tiny teaser) without breaking the gate's magic. |
| **One job, three incumbents** (graffiti / reviews / Pokémon GO) | **Layers/Tags** lets the ambient, utility, and collection jobs coexist without diluting each other — validate this early. |
| **Monitor stage is thin** (Stage 6) | Define the "did anyone hear mine?" loop (play counts, light reactions) — critical for Darnell's social outcome, optional for Maya. |
| Social dimension **splits the personas** | Anonymity by default serves the core job; recognition/status is an *opt-in layer*, not the default (informs open Q8). |

---

## Top 3 JTBD-driven bets

1. **Win "is anyone human near me right now?"** — the single most underserved, highest-value outcome. Gated entirely on solving cold-start density. *Do this first.*
2. **Make "leave a trace without performing" frictionless and safe** — the emotional core for the primary persona; unblock the create loop with privacy reassurance + speed.
3. **Lane the three jobs with Layers/Tags** — so ambient (Maya), utility (Darnell), and collection (Greg) each beat their *own* incumbent without colliding.

---

## Research gaps
- Job statements are **synthesized** — validate the real "hire" and "fire" triggers in interviews (ask about the *last time* they wanted to feel connected to a place and what they actually did).
- **Confirm vs. magic tradeoff** — does any "is this worth the walk?" signal spoil the serendipity? Test it.
- **Which job dominates at scale** — is Soapstone primarily hired for the ambient, utility, or collection job? Determines positioning and which incumbent to attack first.

**Next:** `/interview` to validate hire/fire triggers, or `/test-plan` for the cold-start and walk-to-unlock moments of truth.
