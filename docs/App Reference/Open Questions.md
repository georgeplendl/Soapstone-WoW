# Open Questions

Living document. Add new questions as they arise; mark resolved ones with the decision and date.

---

## Onboarding

1. **Slide count** — App Spec says "5 slides max"; MVP Draft says "≤3 slides max." Which is correct?
2. **Skippable slides** — Should the onboarding carousel have a skip button, or is the always-visible footer CTA (Sign Up / Log In) sufficient?
3. **Tutorial replay** — Should the Welcome Tutorial be replayable from the Profile/Settings screen?

## Sign-up Flow

4. **Back button on Location permission step** — Account is already created at that point. Is there a back button, and if so, what does it do?

## Listening Pane

5. **Auto-play on open** — Does audio auto-play when the listening pane opens, or wait for a tap?
6. **Mid-playback gate exit** — If a user walks out of the 1-mile gate while audio is playing, does the current playback finish before the stone re-locks?

## Recording

7. **Max recording length** — Confirmed at 30 seconds?
8. **Microphone permission timing** — Request during onboarding (alongside location/notifications) or on the user's first record attempt?
9. **Audio editing** — Should users be able to trim their recording after the review screen (optional feature)?
10. **Upload failure / drafts** — If upload fails, is the recording saved locally as a draft with a retry prompt?

## Content & Privacy

11. **Anonymity** — Are stones anonymous by default, attributed to a username, or user-selectable? (MVP Draft says anonymous by default.)
12. **Stone lifespan** — Do stones live forever at MVP, or expire after a TTL? (MVP Draft says indefinite at MVP.)
13. **Per-user drop limits** — Can a user drop unlimited stones, or is there a per-day/per-location cap?

## Nearby Count

14. **Zero nearby state** — When there are no unlocked stones nearby, does the top-bar count show `● None nearby` or hide entirely?
