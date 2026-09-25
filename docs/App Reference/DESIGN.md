# Design: Soapstone

**Author(s):** George Plendl

**Status:** Draft

**Last updated:** 2026-04-28

**Reviewers:** None

---

## Overview

Soapstone is a location-based audio messaging app where users leave short voice recordings ("soapstones") pinned to the physical spot where they were recorded. Other users can hear a soapstone only if they are physically within a 1-mile radius of where it was dropped — step outside that radius and the stone goes silent. The mechanic is inspired by the orange soapstone messages in _Dark Souls_: ambient, anonymous-feeling, and rooted in place.

## Background / Context

- No existing audio messaging app ties content to physical proximity in this way; the closest analogues are geo-tagged social posts (Snapchat Snap Map, Yik Yak) but none gate *playback* by real-time proximity.
- The 1-mile gate is the core product differentiator — it enforces locality and creates serendipity. All UX decisions downstream flow from this constraint.
- The app requires three OS permissions (location, microphone, notifications), each of which needs a deliberate request strategy to avoid permission fatigue.
- Several cross-cutting product decisions (anonymity, stone lifespan, drop limits, moderation) are unresolved and must be finalized before coding starts.

## Goals

- Build a working end-to-end flow: onboarding → account creation → drop a soapstone → hear a soapstone.
- Enforce the 1-mile proximity gate for audio playback.
- Deliver a map-centric home screen with real-time pin updates.
- Implement the recording flow (tap-and-hold FAB, 30-second cap, review-before-drop).
- Support the minimum moderation surface needed for app store approval (report, block).

## Non-Goals

- Full specs for **My Stones**, **Activity/Notifications**, and **Profile** screens — these are stubs only in this doc and will be spec'd separately.
- Backend infrastructure design (storage, CDN, review pipeline) — out of scope for this document.
- Auto-transcription / accessibility enhancements beyond minimum affordances (duration, distance).
- Web or desktop clients — mobile only for v1.

## Requirements

### Functional

- Users can create an account via email + 6-digit verification code, location permission grant, notification permission grant, and username/password setup (5-step flow).
- A swipeable 5-slide onboarding carousel precedes account creation; footer CTAs (`Log In`, `Sign Up`) are always visible.
- After first sign-up, a non-skippable 3-step coach-mark tutorial runs over the home screen.
- The home screen is a full-screen map centered on the user's GPS position; the 1-mile gate is rendered as a radius circle.
- Map pins distinguish unlocked (within gate) from locked (outside gate) stones.
- Tapping any pin opens the Floating Listening Pane; unlocked stones auto-play, locked stones show a "walk closer" message.
- The FAB (bottom-center) triggers recording on tap-and-hold; dragging off cancels.
- Recordings are capped at 30 seconds; a review screen is shown before the stone is dropped.
- The stone is pinned to the user's GPS coordinates at the moment recording *started*.
- Upload failures queue the recording locally for retry.
- A 3-dot overflow menu in the listening pane offers Report, Block user, and Share actions.
- My Stones, Activity, and Profile tabs are present in the tab bar (stub screens acceptable for v1).

### Non-Functional

- Proximity check must use real-time GPS; the gate must not shift when the user pans the map.
- The map must degrade gracefully with no network (cached tiles, no new pins until connectivity returns).
- Audio recording must queue for upload when offline.
- Location permission denial must show a soft-block with a deep-link to OS settings (not a hard crash).
- Microphone permission is requested on first record attempt, not during onboarding.
- Waveform playback animation must react 1:1 with audio.
- Only one stone may play at a time; opening a new pane stops the previous audio.
- All list and map views must have defined empty states.
- Audio load failure, upload failure, network timeout, and auth expiry each need a defined error UX.

## Proposed Design

### High-Level Architecture

```
[Onboarding Carousel]
        ↓
[Sign Up Flow (5 steps: email → verify → location → notifications → username/password)]
        ↓
[Home Screen (Map)] ←→ [Floating Listening Pane]
        ↓
[FAB: tap-and-hold] → [Recording Flow] → [Review Screen] → [Drop Confirmation]
        ↓
[Tab Bar: Home | My Stones | Activity | Profile]
```

### Components

#### Onboarding Carousel
- 5 full-screen slides, swipeable (tap right/left half or horizontal swipe).
- Segmented progress bars at the top; persistent `Log In` / `Sign Up` footer.
- No auto-advance, no skip button.

#### Sign Up Flow
- **Step 1 — Email:** single input, `Continue` disabled until valid email format.
- **Step 2 — Email Verification:** 6-box segmented input, auto-advance, paste-friendly; resend with 60-second cooldown; wrong code turns inputs red and clears them.
- **Step 3 — Location Permission:** explanatory screen → OS prompt; denial shows soft-block with `Open Settings` and `Try again`.
- **Step 4 — Notification Permission:** explanatory screen → OS prompt; `Not now` skips without blocking.
- **Step 5 — Username & Password:** real-time username availability check (3–20 chars, alphanumeric + underscores); password strength indicator (min 8 chars). `Create account` routes to home + tutorial.

#### Welcome Tutorial (First-Run Overlay)
- 3-step coach-mark / spotlight overlay; non-skippable; `Prev`/`Next` buttons; `Done` on final step.
- Steps: map area → FAB → tab bar.

#### Home Screen
- Full-screen map, user location as pulsing sonar dot, 1-mile gate as radius circle.
- Top bar: logotype (left), nearby count with pulsing dot (right).
- Nearby list: horizontal scrollable pills showing pin icon, distance, relative time.
- FAB: large circular button, bottom-center, above tab bar.
- Recenter button: above nearby list, snaps map to GPS position.
- Empty nearby state: "No stones nearby yet. Drop one?" card opens recording flow.

#### Floating Listening Pane
- Floats over dimmed map; dismiss via `X`, tap-outside, or swipe-down.
- **Unlocked variant:** vertical-bar waveform reacting to audio, scrubber with time/duration, play/pause + restart buttons, metadata row (username, age, distance), 3-dot overflow menu (Report, Block, Share).
- **Locked variant:** lock icon, approximate distance, "Walk within 1 mile to listen." No waveform, scrubber, or overflow menu.

#### Recording Flow
- Press-and-hold FAB → pulsing red ring + elapsed timer + live waveform; haptic tick on start.
- 30-second cap with 5-second countdown warning; drag off FAB to cancel.
- **Review screen:** playback with scrubber, `Re-record` and `Drop here` buttons, mini-map showing drop location.
- **Drop confirmation:** upload → success toast → return to home with new pin visible.
- Upload failure → local draft + retry offer.

### Data Model

| Entity | Key Fields |
|--------|-----------|
| **User** | `id`, `email`, `username`, `created_at`, `avatar_url` |
| **Stone** | `id`, `author_id`, `audio_url`, `lat`, `lng`, `created_at`, `expires_at`, `play_count` |
| **Report** | `id`, `reporter_id`, `stone_id`, `reason`, `created_at` |
| **Block** | `id`, `blocker_id`, `blocked_id`, `created_at` |

### APIs / Interfaces

- `POST /auth/email` — send verification code
- `POST /auth/verify` — confirm 6-digit code, return session token
- `POST /auth/signup` — finalize account (username, password)
- `GET /stones?lat=&lng=&radius_miles=1` — fetch stones within radius
- `POST /stones` — upload audio + GPS coordinates → create stone
- `GET /stones/:id/audio` — stream audio file
- `POST /stones/:id/report` — submit a report
- `POST /users/:id/block` — block a user

### User Experience (if applicable)

See Sections 1–7 of the App Specification for detailed screen-by-screen flows. Key interaction decisions:

- **Onboarding:** no skip, always-available footer CTAs.
- **Sign up:** linear 5-step flow with back navigation (Step 3 has no back — account already created at that point; **pending product confirmation**).
- **Tutorial:** non-skippable on first run; replay from Profile/Settings is **recommended but unconfirmed**.
- **Listening pane:** auto-plays on open (**pending product confirmation**); mid-playback gate exit continues until pane closes.
- **Recording:** tap-and-hold only; drag-off cancels; stone location locked to GPS at recording start.

## Alternatives Considered

### Alternative 1: Proximity check on the server only
- Calculate the gate server-side and refuse to serve audio if the requesting user is out of range.
- Not chosen as the sole mechanism because it introduces latency on every play attempt and doesn't allow the map to show locked/unlocked state responsively. Client-side distance math is used to drive UI; server-side enforcement is the authoritative gate.

### Alternative 2: Request microphone permission during onboarding (Step 4)
- Batch all permission requests upfront alongside location and notifications.
- Not chosen because it increases permission fatigue at a point where the user hasn't yet experienced the app's value. Microphone is requested on first record attempt instead.

### Alternative 3: Tap-to-record instead of tap-and-hold
- Standard record button (tap to start, tap again to stop).
- Not chosen — tap-and-hold is a natural anti-spam mechanic and creates a more intentional "drop" gesture consistent with the Dark Souls metaphor.

## Trade-offs

- **Client-side gate vs. pure server enforcement:** faster UI at the cost of a second enforcement layer required on the backend. If skipped, a motivated user could spoof GPS to play any stone.
- **Auto-play on pane open:** more immersive but may surprise users in quiet environments. Needs product sign-off.
- **No skip on onboarding:** lower funnel drop-off risk in exchange for ensuring all users understand the 1-mile mechanic before they interact with the map.
- **Stone location = GPS at recording start:** simple and deterministic, but the user may move during recording. Accepted tradeoff for v1.

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| GPS inaccuracy causes gate edge to flicker | Med | Med | Apply a small hysteresis buffer (~50m) on gate transitions |
| User denies location permission → app is unusable | High | High | Soft-block screen with clear explanation and deep-link to settings |
| Audio upload fails on spotty network | High | Med | Local draft queue with automatic retry on reconnect |
| Abusive/illegal audio content | High | High | Report flow + backend moderation pipeline before launch; required for app store approval |
| App store rejection for insufficient moderation | Med | High | Implement report/block flows and human review pipeline before submission |
| Stone spam (unlimited drops) | Med | Med | Per-user drop limit (rate or cap) — exact value TBD |
| GPS spoofing to bypass the 1-mile gate | Low | Med | Server-side enforcement as authoritative check |

## Rollout Plan

- **Phase 1 — Internal alpha:** onboarding, sign-up, map + pins, listening pane (playback only), recording flow. No moderation UI yet.
- **Phase 2 — Closed beta:** add report/block flow, My Stones stub, Activity stub, Profile stub. Gate on invite codes.
- **Phase 3 — App store submission:** moderation pipeline live, all soft-block/error states complete, accessibility minimums met, analytics instrumented.
- **Rollback strategy:** feature-flag the FAB to disable recording if a critical upload bug is found post-launch without pulling the entire release.

## Testing Strategy

- **Unit tests:** distance calculation (1-mile gate math), audio timer/countdown logic, form validation (email, username, password rules), verification code error states.
- **Integration tests:** sign-up happy path end-to-end, stone drop + retrieval by second user within range, stone locked for user outside range.
- **Manual QA:** all OS permission grant/denial flows, mid-playback gate exit behavior, drag-off-FAB cancel, paste into verification input, 30-second recording cap countdown.
- **Device testing:** iOS and Android on at least two screen sizes each; test in low-GPS-accuracy environments.

## Observability

- **Sign-up funnel:** events at each step (step_viewed, step_completed, step_abandoned) to track drop-off by step.
- **Permission events:** `permission_requested`, `permission_granted`, `permission_denied` for location, microphone, and notifications.
- **Stone drops:** `stone_recorded`, `stone_dropped`, `stone_upload_failed`, `stone_upload_retried`.
- **Stone plays:** `stone_play_started`, `stone_play_completed`, `stone_play_abandoned` (with % progress).
- **Gate events:** `stone_unlocked` / `stone_locked` transitions as user moves.
- **Error rates:** audio load failure rate, upload failure rate, auth expiry rate — alert if any spike above baseline.

## Open Questions

- [ ] Should the onboarding slides be skippable? — needs product decision
- [ ] Should the Welcome Tutorial be replayable from Settings? — recommended yes, pending product confirmation
- [ ] Is there a back button on the Location Permission step (Step 3)? Account is already created at that point — confirm with product
- [ ] Should audio auto-play when the listening pane opens, or wait for a tap? — pending product confirmation
- [ ] If a user walks outside the gate mid-playback, does the current playback finish? — pending product confirmation
- [ ] Max recording length — confirming 30 seconds?
- [ ] Microphone permission placement confirmed as first-record (not onboarding)?
- [ ] Are stones anonymous or attributed to usernames? — affects listening pane metadata and privacy model
- [ ] Do stones expire? Proposing 30-day TTL with optional extension mechanic — pending product decision
- [ ] Per-user drop limits (rate or cap)? — needed to prevent spam

## References

- `docs/Soapstone — App Specification.md` — primary source for all screen flows and UX decisions in this document
