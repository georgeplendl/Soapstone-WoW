# Changelog

All notable changes to the Soapstone addon. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/). While the addon is `0.x`, a minor
version can change saved data or behaviour.

Each release's notes on GitHub come from its section below, so write entries
for players: what changed in game, not how.

## [Unreleased]

### Changed
- "Edit Soapstone" shows your message exactly as it will read: the same
  text size as the stone window, centred, and wrapping at the same width.

## [0.3.2] - 2026-09-25

### Changed
- **"Leave a Soapstone"** picks between a message and a drawing with
  **Write** and **Draw** buttons at the top, instead of small tabs under the
  window. The chosen one stays lit, and it always opens on **Write**.
  Opening it closes any stone you had open, and any edit in progress (as if
  cancelled).
- **The stone window:**
  - written stones are shown in quotes, in larger text, and wrap wider;
  - who left it sits just under the stone;
  - Appraise and Disparage share the bottom row with Edit, with more room
    between them.
- Your own stones are signed with your name and "(You)", e.g. "— Mad
  Decent (You), 24 mins ago", and ages read naturally everywhere ("1 min
  ago", "3 hrs ago", "5 days ago").

## [0.3.1] - 2026-09-25

### Changed
- **Sharing with other players is now off by default.** Soapstone no longer
  joins its hidden network channel unless you turn networking on with
  `/soap net join` (`/soap net leave` turns it off again). This applies to
  existing installs too: updating from 0.3.0 switches it off. Your stones,
  appraisals and everything else work the same without it.

## [0.3.0] - 2026-09-25

### Added
- **Appraise and Disparage**, as in Dark Souls. Every stone's window has
  **Appraise** and **Disparage** under the message or drawing, and its
  **appraisals** at the right of the title bar.
  - Your own stones start appraised (1 appraisal). You can withdraw that or
    disparage your own stone, but it never goes below 0.
  - On other players' stones, appraise or disparage; press again to
    withdraw. Appraised stones get a gold minimap pin; disparaged ones fade
    and stop calling you over with sound cues.
  - Appraisals are personal for now: they count the author's appraisal plus
    your own characters' judgements.
- **Edit and delete your sketches**, like written stones: "Edit Soapstone"
  opens the drawing editor with your drawing loaded.
- `/soap stats` shows how many stones are stored, and where.
- `/soap version` also says which build is running (the release, or the
  development branch).

### Changed
- The stone window is laid out afresh: Appraise and Disparage under the
  stone, a divider, then Edit (on your own stones) and who left it.
- Sketches show **larger** when read (3× instead of 2×, the size they're
  drawn at), with equal space above and below a stone.
- The 5-minute edit window now **pauses while the edit dialog is open** (a
  slow edit costs nothing; cancelling picks up where it paused) and
  **restarts from a full 5 minutes each time you save an edit**.
- Stones are signed with your full character name ("Mad Decent" on WoW
  Forever); your earlier stones are relabelled automatically.
- Only the character who wrote a stone can edit or delete it. Before, any
  character on the same account could.
- New storage format. Your stones are upgraded automatically the first time
  you log in; **older versions of Soapstone can't read the new format.**
- The minimap and proximity checks only look at stones near you, so they
  stay fast however many stones are stored.

### Experimental: sharing stones between players
- **Zone sync.** A few seconds after login Soapstone quietly joins a hidden
  channel. When you settle in a zone it asks other Soapstone players online
  for that zone's stones and fetches the ones you don't have ("12 new
  stones arrived for The Barrens"). Edits and deletions only take effect
  when they come from the stone's author. `/soap sync` shows what's
  happening; `/soap sync now` asks again.
- `/soap net` test tools (`selftest`, `pacetest`, `status`, `ping`,
  `burst`, `log`) check that Soapstone players can reach each other.
- This hasn't been tried between two real players yet, and sharing may move
  to a companion app with a proper database for fast, live syncing, so
  expect it to change.

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

[Unreleased]: https://github.com/georgeplendl/Soapstone-WoW/compare/v0.3.2...HEAD
[0.3.2]: https://github.com/georgeplendl/Soapstone-WoW/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/georgeplendl/Soapstone-WoW/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/georgeplendl/Soapstone-WoW/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/georgeplendl/Soapstone-WoW/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/georgeplendl/Soapstone-WoW/releases/tag/v0.1.0
