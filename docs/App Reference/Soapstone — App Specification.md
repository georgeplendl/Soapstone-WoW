## Concept

Soapstone is a location-based audio messaging app. Users leave short voice recordings ("soapstones") pinned to the physical spot where they were recorded. Other users can hear a soapstone only if they are physically within a 1-mile radius of where it was dropped. Step outside that radius and the stone goes silent — visible on the map as "locked," but unplayable.

The name and mechanic are inspired by the orange soapstone messages in _Dark Souls_: ambient, anonymous-feeling, rooted in place.

---

## 1. Onboarding Slides

A full-screen, swipeable intro carousel (Instagram Stories pattern) that introduces the app before account creation.

- **Count:** 5 slides max.
- **Advance:** tap right half to advance, tap left half to go back, or swipe horizontally.
- **Progress:** segmented progress bars along the top, one segment per slide, filling as each slide is viewed.
- **Persistent footer:** two static buttons pinned to the bottom of the screen across all slides — `Log In` (secondary) and `Sign Up` (primary). Footer does not animate between slides.
- **Auto-advance:** off. User controls pacing.
- **Skippable:** no skip button — the slides are short and the footer CTAs are always available, so the user can exit the flow at any time by tapping `Sign Up` or `Log In`.

**Suggested slide content** (finalize with design/copy):

1. What a soapstone is — "Leave a voice message in the real world."
2. The 1-mile gate — "Only people nearby can hear it."
3. Dropping a stone — "Tap and hold to record. Let it go to drop."
4. Discovering stones — "Walk into range. Listen in."
5. Welcome — closing frame, CTAs emphasized.

---

## 2. Account Creation / Sign Up

A 5-step linear flow. Each step has a back arrow in the top-left.

### Step 1 — Email

- Single input: email address.
- Primary button: `Continue` (disabled until a valid email format is entered).
- Back arrow returns to the onboarding slides, **restarting from slide 1**.
- Link below the input: "Already have an account? **Log in**."

### Step 2 — Email verification (2FA)

- Six-digit code sent to the email from Step 1.
- Six segmented input boxes; auto-advance between boxes; paste-friendly.
- `Resend code` link, disabled with a 60-second countdown (`Resend in 0:54`). Re-enables after countdown.
- Error state: if the code is wrong, inputs turn red, a message reads "That code didn't match. Try again." and the inputs clear.
- Link at the bottom: "Already have an account? **Log in**."
- Back arrow returns to Step 1 (email input, pre-filled with the email just entered).

### Step 3 — Location permission

- Explanatory screen, then the system permission prompt.
- Heading: "We need your location."
- Body: "Soapstones are only audible within 1 mile of where they were left. Step outside this gate — and they vanish."
- Primary button: `Allow location` → triggers the OS permission dialog.
- If the user denies: show a soft-block screen explaining the app can't function without location, with a `Open Settings` button (deep-links to the OS settings page for the app) and a secondary `Try again` button.
- No back arrow on this step — account has been created; there is no prior step to return to. _(Flag for product: confirm this.)_

### Step 4 — Notification permission

- Heading: "Don't miss a beat."
- Body: "Get notified about new stones in your area."
- Primary button: `Turn on notifications` → triggers OS prompt.
- Secondary button: `Not now` (allows skipping without blocking).

### Step 5 — Username and password

- Inputs: username, password.
- Username rules: 3–20 characters, alphanumeric plus underscores, must be unique. Show real-time availability check.
- Password rules: minimum 8 characters; show strength indicator. _(Finalize rules with security.)_
- Primary button: `Create account` — on success, routes to the home screen with the tutorial overlay.

---

## 3. Welcome Tutorial (first-run overlay)

A coach-mark / spotlight tutorial that runs once immediately after account creation, overlaid on the home screen.

- **Non-skippable.** No dismiss button on any step.
- **Navigation:** `Prev` and `Next` buttons. `Prev` is hidden on Step 1. On the final step, `Next` is replaced by `Done`.
- **Dimming:** the rest of the screen is dimmed; the highlighted element is cut out and fully visible.

**Steps:**

1. **The map.** Spotlight the center of the map. "This is your area. Explore local Soapstone drops here."
2. **The record button.** Spotlight the FAB. "Tap and hold to drop a Soapstone of your own."
3. **The bottom toolbar.** Spotlight the tab bar. "Find everything else here — your stones, activity, and profile." → button reads `Done`.

After `Done`, the overlay dismisses and the tutorial never re-appears. _(Flag for product: should there be a way to replay it from the profile/settings screen? Recommended.)_

---

## 4. Home Screen

The map is the home screen. It fills the entire viewport; other elements float on top.

### Top bar (overlay)

- Left: Soapstone logotype.
- Right: nearby count with a pulsing dot — e.g. `● 3 nearby`. Pulses at ~1 Hz. Count reflects unlocked stones within the 1-mile gate. If zero, display `● None nearby` (or hide — _decide_).

### Map

- Default view: centered on the user's GPS position, zoomed so the 1-mile gate is visible with a small margin.
- **User location:** a solid circle at the center, with a sonar pulse animation emanating outward (~2 second period).
- **The gate:** a 1-mile radius circle around the user. Rendered as a soft fill plus a visible border — the "gate" edge.
- **Pins:**
    - _Unlocked_ (within the gate): plain pin icon.
    - _Locked_ (outside the gate, or anywhere the user pans the map to): pin-with-lock icon.
- **Panning:** the user can pan and zoom freely anywhere in the world. Locked stones load as they scroll into view. The user location and gate remain tied to actual GPS, not the map center — panning away does not move the gate.
- **Recenter:** a small button (compass or crosshair icon) above the Nearby list snaps the map back to the user's GPS location.
- **Tapping a pin** — unlocked or locked — opens the Floating Listening Pane.

### Nearby list (bottom, above FAB)

- Horizontal scrollable row of pill/card buttons.
- Subheading: `Nearby`.
- Each card shows:
    - Pin icon
    - Distance — e.g. `0.4 mi`
    - Relative time — e.g. `4 mins ago`, `a month ago` (rough, human-readable)
- Tapping a card opens the Floating Listening Pane for that stone and optionally animates the map to center on its pin.
- **Empty state:** if there are no unlocked stones nearby, show a single card: "No stones nearby yet. Drop one?" that opens the record flow when tapped.

### FAB (record button)

- Large circular button, bottom-center, above the tab bar.
- **Interaction:** tap-and-hold to start recording. Release to stop. See [§6 Recording Flow](https://claude.ai/chat/3b26afd2-f909-45e2-b9ca-6c7cc0536938#6-recording-flow).

### Tab bar (bottom)

Four tabs: `Home`, `My Stones`, `Activity`, `Profile`. See [§7 Other Screens](https://claude.ai/chat/3b26afd2-f909-45e2-b9ca-6c7cc0536938#7-other-screens-stubs).

---

## 5. Floating Listening Pane

A modal-ish pane that floats over the map, with the map still partially visible behind it (dimmed).

### Opens when

- User taps an **unlocked** pin on the map.
- User taps a card in the Nearby list.
- User taps a **locked** pin → opens in a reduced "locked" variant (see below).

### Unlocked variant

- **Close affordances:**
    - `X` button in the top-right of the pane.
    - Tapping the dimmed map area outside the pane also dismisses it.
    - Swipe-down to dismiss (standard iOS/Android sheet gesture).
- **Content:**
    - Vertical-bar waveform that reacts 1:1 with the audio as it plays.
    - Playback scrubber with current time and total duration (e.g. `0:07 / 0:22`).
    - Center: primary play/pause toggle.
    - Right of play: restart-from-beginning button.
    - Top-right (next to close): 3-dot overflow menu. **Options: Report, Block user, Share.** _(TBD confirmed — proposing these three.)_
    - Metadata row: poster's username (or "Anonymous" — _see privacy question below_), how long ago it was dropped, distance from user.

### Locked variant (user tapped a pin outside the gate)

- Same pane frame, but playback is disabled.
- Shows: a lock icon, the stone's location as an approximate distance ("2.3 mi away"), and the message "Walk within 1 mile to listen."
- Close affordances identical to the unlocked variant.
- No waveform, no scrubber, no overflow menu (nothing to report yet — the user hasn't heard it).

### Playback behavior

- Auto-plays on open. _(Flag for product: confirm. Alternative is tap-to-play.)_
- If the user walks out of the 1-mile gate mid-playback: audio continues to the end of the current playback session, but the stone re-locks once the pane is closed. _(Flag for product: confirm this rule.)_
- Only one stone can play at a time. Opening a new pane stops the previous audio.

---

## 6. Recording Flow

_(This section was missing from the original spec — proposing a full flow.)_

Triggered by press-and-hold on the FAB.

1. **Hold to record.**
    
    - On press, FAB expands and a recording indicator appears (pulsing red ring, elapsed timer, live waveform).
    - Haptic tick at start.
    - Max length: **30 seconds**. _(Proposed — confirm.)_ A countdown appears in the last 5 seconds.
    - Release finger to stop. Recording is also auto-stopped at the 30-second cap.
    - If the user drags their finger off the FAB before releasing (iOS Messages pattern): cancel and discard.
2. **Review screen.** Full-screen takeover after release.
    
    - Playback of the recording with scrubber.
    - Buttons: `Re-record` (discards and returns to home), `Drop here` (primary).
    - Shows the drop location on a mini-map preview — the stone will be pinned to the user's GPS coordinates _at the moment recording started_.
3. **Drop confirmation.**
    
    - On `Drop here` → upload, success toast ("Stone dropped."), return to home. The new pin appears on the map and at the top of the Nearby list.
    - If upload fails: keep the recording in a local "drafts" state and offer retry. _(Flag: confirm drafts behavior.)_
4. **Microphone permission.**
    
    - First-ever record attempt triggers the mic permission prompt. If denied, show a soft-block with deep-link to settings.
    - Should be requested on first record rather than during onboarding, to reduce permission fatigue. _(Flag: confirm placement.)_

---

## 7. Other Screens (stubs)

These are referenced in the tutorial but not spec'd in the original doc. Calling them out so they don't get lost.

- **My Stones** — list of stones the current user has dropped. Probably: thumbnail/waveform, location, date, play count, delete action.
- **Activity / Notifications** — feed of events: someone listened to your stone, someone reported a stone, new stones in your area, etc.
- **Profile** — username, avatar, stats (stones dropped, total listens), settings link. Settings should include: notification prefs, logout, delete account, replay tutorial, report-a-problem, terms/privacy links.

Full specs for these are **out of scope for this doc** and should be written separately.

---

## 8. Cross-cutting concerns

Flagging these because they affect multiple screens and need product decisions before coding starts.

- **Privacy / anonymity.** Are stones attributed to a username, or anonymous? The listening pane currently shows the poster — confirm. If attributed, we need a way for the poster to block themselves from being found via that username.
- **Moderation.** User-generated audio requires a report flow (proposed in the 3-dot menu) and a backend review pipeline. Needed for app store approval.
- **Stone lifespan.** Do stones live forever, or expire? Proposing a TTL (e.g. 30 days) with an extension mechanic. _(Product decision.)_
- **Content limits per user.** Can a user drop unlimited stones? Per day? Per location? Needed to prevent spam.
- **Offline behavior.** What happens with no network? Map should degrade gracefully; recording should queue for upload when connectivity returns.
- **Permission denial recovery.** Each of location, notifications, and microphone needs a soft-block screen with a deep-link to settings when the user has previously denied.
- **Empty states.** Every list/map view needs a defined empty state (no stones nearby, no activity, no dropped stones yet).
- **Error states.** Audio load failure, upload failure, network timeout, auth expired — each needs a defined UX.
- **Analytics.** Define events before building: sign-up funnel steps, stone drops, stone plays, permission grants/denials.
- **Accessibility.** Voice content must have some non-audio affordance — at minimum, duration and distance; ideally, optional auto-transcription.

---

## 9. Open questions

Consolidated for easy review:

1. Should the onboarding slides be skippable?
2. Should the Welcome Tutorial be replayable from settings?
3. Is there a back button on the Location permission step? (Account is created at that point.)
4. Should audio auto-play when the listening pane opens, or wait for a tap?
5. If a user walks out of the gate mid-playback, does the current playback finish?
6. Max recording length — 30 seconds?
7. Microphone permission: request during onboarding or on first record?
8. Are stones anonymous or attributed to usernames?
9. Do stones expire?
10. Per-user drop limits?
11. Should the user be able to edit/trim their audio (optional) after recording?