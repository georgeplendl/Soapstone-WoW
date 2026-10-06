# Changelog

All notable changes to the Soapstone addon. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/). While the addon is `0.x`, a minor
version can change saved data or behaviour.

Each release's notes on GitHub come from its section below, so write entries
for players: what changed in game, not how.

## [Unreleased]

### Fixed
- **Stones can't carry WoW formatting codes any more.** A stone's words, or
  a player's name, could include codes for colours, links or pictures, and
  the game drew them in tooltips, chat and the stone window, so a stone
  could pass itself off as a system message. They now always show as
  plain text.
- **A stone can't take over another player's stone.** A stone claiming the
  same id as one by someone else is refused, so nobody can replace your
  stones in other players' games.

## [0.5.0] - 2026-10-06

### Added
- **Stones on the world map.** Every stone you know of now shows on the
  world map, so there's always somewhere to head for. Sealed stones (ones
  you haven't been to yet) are bigger and glow softly. Stones you've read
  and your own sit back, and appraised ones are gold. Hovering a pin says
  how far away it is and in which direction, but never what it says: you
  still have to stand where it was left to read it.
- **A count under the world map:** "Durotar: 4 sealed soapstones to find ·
  2 read", for whichever zone or continent you're looking at.
- **Guide me there.** Click a stone's pin on the world map, or type
  `/soap guide` for the nearest sealed stone. With **TomTom** installed,
  its arrow points the way. Without it, Soapstone uses the game's own map
  pin and in-world marker. The waypoint clears itself
  once you're close enough to read the stone, and a map pin you set
  yourself is never touched. `/soap guide off` stops guiding.
- **The Soapstone companion (early preview).** A small app for your
  system tray that shares stones between players through a shared
  database, and installs and keeps Soapstone up to date for you. This
  release includes a first preview, `Soapstone-Companion-v0.1.0-setup.exe`.
  It talks to a test server on your own PC, so it doesn't share stones with
  other players yet; a public server comes next.
  - With the companion running, Soapstone loads its stones (and drawings)
    when you log in or `/reload`, and tells you if a stone of yours couldn't
    be shared, and why. The minimap button's tooltip and `/soap stats` say
    when it last synced.
  - Soapstone keeps a list of your drops, edits, deletes, appraisals and the
    stones you've opened, for the companion to upload, including stones you
    left before this update. `/soap stats` shows how many are waiting.
- **Sync.** Shift-click the minimap button, or type `/soap sync`, to share
  your latest changes and pick up new stones from the companion right away
  (it reloads your UI). The old player-to-player zone sync moved to
  `/soap net sync`.

### Fixed
- **Stones missing since the October 5 beta patch are back.** The patch
  changed how WoW Forever identifies itself, so Soapstone took it for a
  different game and hid every stone left before it. Stones dropped since
  then were filed under the wrong game too. All of them show again.

### Changed
- **Each character reads stones for themselves.** A stone your main has
  read is still sealed for your alts until they've stood there too,
  including stones your other characters left. Stones you'd already read
  before this update stay read for everyone.

## [0.4.1] - 2026-09-25

### Removed
- The chime when you reach a stone you can read. The "somewhere close" cue
  still plays as you approach, and the minimap button still glows while
  you're in range.

## [0.4.0] - 2026-09-25

### Added
- **Sounds:** a crystal settling into place as you set a stone down, and an
  aura fading away as you delete one. `/soap sound off` mutes them with the
  other cues.
- `/soap sound <cue>` previews any sound cue (`near`, `read`, `appraise`,
  `disparage`, `drop`, `delete`) and names the sound it played.

### Changed
- **What you type is what they'll read:** writing a stone ("Leave a
  Soapstone" → Write) and editing one ("Edit Soapstone") use the same
  message box, in the stone window's text size, centred, and wrapping at
  the same width. On Write the window sits snugly around the box; Draw
  grows it for the drawing editor.
- "Edit Soapstone" no longer shows an "Editable for …" countdown: the clock
  is paused while you edit, and the stone's Edit button shows the time
  left.

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

[Unreleased]: https://github.com/georgeplendl/Soapstone-WoW/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/georgeplendl/Soapstone-WoW/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/georgeplendl/Soapstone-WoW/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/georgeplendl/Soapstone-WoW/compare/v0.3.2...v0.4.0
[0.3.2]: https://github.com/georgeplendl/Soapstone-WoW/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/georgeplendl/Soapstone-WoW/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/georgeplendl/Soapstone-WoW/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/georgeplendl/Soapstone-WoW/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/georgeplendl/Soapstone-WoW/releases/tag/v0.1.0
