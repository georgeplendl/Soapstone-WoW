# Changelog

All notable changes to the Soapstone addon. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/). While the addon is `0.x`, a minor
version can change saved data or behaviour.

Each release's notes on GitHub come from its section below, so write entries
for players: what changed in game, not how.

## [Unreleased]

### Added
- Soapstone quietly joins a hidden network channel a few seconds after login,
  the groundwork for sharing stones between players. It doesn't sync stones yet.
- `/soap net` test tools: `selftest` and `pacetest` (work with a single character),
  `status`, `ping`, `burst` and `log`, to check that Soapstone players can
  reach each other.

- `/soap stats` shows how many stones are stored, and where.
- **Edit and delete your sketches** too, within the same 5-minute window as
  written stones: "Edit Soapstone" opens the drawing editor with your
  drawing loaded.
- **Appraise and Disparage**, as in Dark Souls: every stone's read window
  has **Appraise** and **Disparage** centred under the message or sketch,
  with Edit and the author's name below a rule, and the stone's
  **appraisals** at the right of the title bar. Your own
  stones start appraised (1 appraisal), and
  disparaging your own only withdraws that, down to 0. On other players'
  stones, appraise or disparage (press again to withdraw): appraised stones
  get a gold minimap pin, disparaged ones fade and no longer trigger sound
  cues. Scores count the author's appraisal plus your own characters'
  judgements; they're personal for now.
- `/soap version` also says which build is running: the git branch and
  commit in a development checkout, or the release tag in a release zip.
- **Zone sync:** settle in a zone for a few seconds and Soapstone asks other
  Soapstone players online for that zone's stones, then fetches the ones you
  don't have ("12 new stones arrived for The Barrens"). Stones you receive
  show their author; edits and deletions only take effect when they come
  from the author. `/soap sync` shows what's happening; `/soap sync now`
  asks again.

### Changed
- Stones are signed with your full character name ("Mad Decent" on WoW
  Forever), and your earlier stones are relabelled automatically.
- Only the character who wrote a stone can edit or delete it. Before, any
  character on the same account could.
- New storage format, ready for sharing. Your stones are upgraded
  automatically the first time you log in; **older versions of Soapstone
  can't read the new format.**
- The minimap and proximity checks only look at stones near you, so they
  stay fast however many stones are stored.
- Sketches show **twice as large** in the read window (4× instead of 2×),
  and there's equal space above and below a stone's message or drawing.
- The 5-minute edit window now **pauses while the edit dialog is open** (a
  slow edit costs nothing; cancelling picks up where it paused) and
  **restarts from a full 5 minutes each time you save an edit**.

## [0.2.0] - 2026-09-25

### Added
- **Stone Sketches.** Stones can now carry a drawing instead of text: a
  160×60 black-and-white canvas inspired by Miiverse and Splatoon's
  mailbox posts.
  - Pen and eraser in three sizes each; left-drag draws, right-drag erases.
  - Undo (up to 50 strokes) and an undoable Clear.
  - Drawn at 3× and read at 2×, snapped to whole screen pixels.
- **"Leave a Soapstone" window** replaces the old popup, with **Write** and
  **Draw** tabs. It remembers your last tab and keeps your draft if you close
  it without dropping.
- **"Soapstone" read window.** Click a readable minimap pin, or type
  `/soap read`, to open a stone. It closes on its own when you walk out of
  range.
- **Edit or delete your written stones** for 5 minutes after dropping them.
  An **Edit (m:ss)** button counts down on the read window and opens the
  "Edit Soapstone" dialog; edited stones are marked "(edited)", and deleting
  asks for confirmation.
- `/soap test` now plants a stranger's sketch half of the time.
- `/soap version` prints the installed version.

### Changed
- New soapstone crystal icon with a transparent background, on the minimap
  button, minimap pins and the AddOns list. It replaces a Blizzard item icon
  that showed as a black square.
- Minimap pins are slightly larger (16 px).

## [0.1.0] - 2026-09-25

### Added
- Drop written stones (up to 140 characters) where you stand, from a
  draggable minimap button or `/soap`.
- Minimap pins for nearby stones. Sealed stones are grey and cling to the
  minimap's rim when out of view, pointing the way.
- Stones open for reading within 40 yards (`/soap radius`).
- Sound cues: a soft ping when an unread stone is within 150 yards
  (`/soap near`) and a chime when you can read one (`/soap sound`).
- `/soap list`, `/soap test`, `/soap button` and `/soap clear`.

[Unreleased]: https://github.com/georgeplendl/Soapstone-WoW/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/georgeplendl/Soapstone-WoW/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/georgeplendl/Soapstone-WoW/releases/tag/v0.1.0
