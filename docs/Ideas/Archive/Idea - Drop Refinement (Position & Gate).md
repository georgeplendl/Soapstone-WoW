#idea, #soapstone, #mechanic

## Drop Refinement — Nudging Position & Sizing the Gate

An **optional** step between recording and posting, where the poster can fine-tune two things about their stone before it goes live:

1. **Reposition** the center of the drop — nudge it off the raw GPS fix, Uber pickup/drop-off style.
2. **Shrink** the gate radius — tighten the listening area below the default 1 mile.

This is deliberately *not* part of the core experience. The base loop stays: hold the button, release, drop. Refinement is an opt-in affordance for people who care about precision — it never gets in the way of a quick drop.

---

### Where It Lives In The Flow

This extends the existing **Review screen** (App Spec §6, step 2) — after the user releases the record button, before they tap `Drop here`.

- The Review screen already shows a mini-map preview of the drop location. Refinement turns that preview into an interactive map.
- A `Refine` affordance (or the map itself being tappable) opens the controls. Skipping it drops at raw GPS with a 1-mile gate — today's behavior.

---

### Control 1 — Reposition the Center (Uber-style)

GPS routinely lands a pin mid-street, on the wrong side of a building, or a few doors down. This lets the poster place the stone where they actually mean — the bench, the doorway, the mural.

- **Interaction:** fixed center pin, drag the *map* underneath it (the Uber / Google Maps pattern). Smoother on mobile than dragging a tiny pin, and the center is always dead-center and legible.
- **The leash (core constraint):** the center can only move within a bounded distance of the true GPS fix — e.g. **~100m** — "within reason." Render the allowed area as a faint circle the pin can't leave. This keeps every stone honestly rooted to where the person physically stood; you're correcting reality, not faking a location across town.
- **Synergy with tight gates:** because the nudge lets a poster correct a bad GPS fix, it directly de-risks small gates — the GPS-drift concern shrinks when the poster can place the center deliberately.

---

### Control 2 — Shrink the Gate

The poster can tighten the listening area, but **never enlarge it past 1 mile.** 1 mile stays the ceiling and the default; the control only moves inward, centered on the (possibly nudged) pin.

- The unlock check becomes `distance(listener, stone) <= stone.radius`, where `stone.radius <= 1 mile`
- Tighter gates make a stone a deliberate "this is *for here*" signal — the opposite of spam

#### Why shrink-only

The bidirectional version (allowing bigger gates) introduces problems shrink-only quietly avoids:

- **No spam vector.** Nobody can blanket a neighborhood with one oversized gate — no caps to enforce.
- **The 1-mile rule stays true.** "Within 1 mile" becomes "within *at most* 1 mile." Nothing reaches a listener from beyond a mile, so the learned rule never breaks.
- **The home-screen gate circle stays honest.** Everything a listener could hear is still inside their 1-mile circle — some stones are just tighter.

#### Tiers (proposed)

| Tier | Radius | Feel |
|---|---|---|
| Spot | ~50m | Hyper-local. A single landmark, bench, or doorway. Must stand on the spot. |
| Block | ~400m | A plaza, a block, a small park. |
| Neighborhood | 1 mi (default / max) | The existing gate. The familiar baseline and the ceiling. |

---

### The Tension (and the answer)

The app's soul is that stones are "pinned to the physical spot where they were recorded." Letting people move the center pushes against that. The **leash** is the answer: a bounded nudge corrects GPS error and lets people be *more* precise about a real place, while a hard cap on offset prevents the feature from becoming "drop a stone anywhere." Refinement should feel like sharpening the truth, not inventing it.

---

### Listener-Side & Map Impact

- The nudged center becomes the canonical drop location for everyone — the pin all listeners see and measure distance from.
- A pin inside your 1-mile circle may still be locked because its own gate is tighter. The **locked listening pane** must state the stone's reach — e.g. "Audible within 50m. Walk closer."
- Draw a stone's own (tighter) gate only when selected; the user's 1-mile circle stays the persistent outer boundary.

---

### Abuse & Limits

Bounded by design. The leash caps how far a center can move; shrink-only caps reach at today's 1 mile. The feature adds **zero** new amplification or relocation beyond a short, deliberate nudge. No additional caps required.

---

### MVP Positioning

Recommend **shipping the fixed 1-mile gate + raw-GPS drop first** — that's the core loop to validate. The whole refinement step is a low-risk fast-follow:

- Backend cost is small: store a `radius` field and the final (post-nudge) coordinates. Nothing else changes.
- Because reach can't exceed 1 mile and the center can't leave the leash, the feature can't regress the core experience.
- It's also a natural home for future precision-flavored rewards/stats (e.g. "precise drops"), tying into the [[First Discovery Bonus]] and quest ideas.

---

### Open Questions

1. **Leash radius** — how far can the center move from true GPS? ~100m? Should it scale with the reported GPS `accuracy` value (more drift allowed when the fix is poor)?
2. **Reposition interaction** — drag-the-map-under-fixed-pin (Uber) or drag-the-pin-directly? (Leaning fixed-pin.)
3. **Gate control** — discrete tiers (above) or a continuous slider that only travels inward from 1 mile?
4. **Gate floor** — is ~50m the tightest, given GPS drift even after a manual nudge?
5. **Post-drop edits** — can a dropper re-refine (reposition / retighten) their own stone later, or is everything locked at drop time?
6. **Visibility** — should a tighter stone's gate hint on the map before selection (a faint smaller ring), or strictly on tap?
7. **Nearby list** — does a tight-gate stone appear in Nearby before you're inside its gate, or only once in range?
8. **Cost** — is refinement always free, or is precision a rewarded/priced action?
