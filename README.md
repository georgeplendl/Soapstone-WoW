# Soapstone for World of Warcraft

> Leave a message somewhere in Azeroth. Only someone standing where you stood can read it.

A World of Warcraft addon spun off from [Soapstone](https://github.com/georgeplendl/Soapstone)
(local checkout: `C:\Users\PC\Documents\Soapstone`), the location-based
voice-message phone app. The two are separate repos, developed independently. It starts from the same idea (the
orange soapstone messages in *Dark Souls*, rooted in place) and is expected to
drift away from the app as it finds what works inside WoW.

The minimap is the trigger surface: a button to drop stones, pins that pull you
toward sealed ones, and sound cues as you close in.

## Layout

- `Soapstone/`: the addon (this folder goes in `Interface\AddOns`)
- `docs/Ideas/`: game-mechanic ideas carried over from the app, free to be reworked for WoW
- `docs/Inspiration.md`, `docs/Project Soapstone Initial Ideas.md`: origin notes
- `docs/App Reference/`: the phone app's spec, MVP, design and research. Reference only.

## Download

Each version is published on the
[Releases page](https://github.com/georgeplendl/Soapstone-WoW/releases) with
its changelog and a `Soapstone-vX.Y.Z.zip`. Unzip it into your client's
`Interface\AddOns` folder so you get `AddOns\Soapstone\Soapstone.toc`, then
restart the game. `/soap version` shows what's installed. Full history is in
[CHANGELOG.md](CHANGELOG.md).

## Install (dev loop)

Target client: the Classic beta install at `D:\Games\World of Warcraft\_classic_beta_` (build `1.60.1.70009`).

Link the addon folder into AddOns so edits are live after `/reload`. From an **admin** Command Prompt:

```
mklink /J "D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns\Soapstone" "C:\Users\PC\Documents\Playground\Soapstone-WoW\Soapstone"
```

**Branch in `/soap version`:** once per clone, turn on the repo's git hooks:

```
git config core.hooksPath .githooks
```

After every checkout, commit, merge or pull they write
`Soapstone/BuildInfo.lua` (git-ignored) with the branch, commit and date,
so `/soap version` shows which build is running. After switching branches,
`/reload` in game to pick it up. To write the file by hand:
`sh tools/buildinfo.sh`.

**Interface version:** `Soapstone.toc` says `16001`, confirmed on the WoW
Forever client with `/dump (select(4, GetBuildInfo()))`. If a client update
changes it, update `## Interface:` (or tick *Load out of date AddOns*).

## Try it

| Action | What happens |
|---|---|
| Left-click minimap button (or `/soap`) | "Leave a Soapstone" window: **Write** tab for a message, **Draw** tab for a sketch |
| Draw tab | 160×60 black-and-white canvas at 3×; 3 pen and 3 eraser sizes; left-drag draws, right-drag erases; Undo, Clear (undoable) |
| Right-click minimap button (or `/soap list`) | Nearest 10 stones with distance + compass direction |
| Click a readable minimap pin (or `/soap read`) | Opens the stone: message, or sketch at 2×. It closes if you walk out of range |
| Open one of your own stones (written or drawn) within 5 min of posting it | **Edit (m:ss)** button counts down; opens "Edit Soapstone" (the message box, or the drawing editor for a sketch) to change it (marked "(edited)") or delete it (with confirmation). The clock pauses while the editor is open, and a saved edit restarts the full 5 minutes |
| `/soap test` | Plants a stranger's stone or sketch 200 yd north of you — walk to it |
| Walk within 150 yd of an unread stone | Soft "somewhere close" ping + notice (re-arms when you walk away) |
| Walk within 40 yd of a stone | Readable chime on every approach, button glows while in range; the first time also prints the message |
| Hover a minimap pin | Message if you're in range; "sealed" + distance if not |
| **Appraise** / **Disparage** in someone else's stone | Rate it (one rating per stone per character; click again to take it back). Appraised pins turn gold; disparaged pins fade and stop triggering sound cues |
| `/soap sound test` | Preview both cues; `/soap sound on\|off` toggles them |
| `/soap radius 25`, `/soap near 100` | Change the read / "somewhere close" ranges |
| `/soap version` | Shows the installed version and which build it is: `0.2.0 (branch ratings @ 16dd7e0, 2026-09-25 18:02)` in a dev checkout, `(release v0.3.0 @ …)` from a release zip |
| `/soap stats` | How many stones are stored (yours, others', test), tombstones, pending changes, and the busiest zones |
| Settle in a zone for a few seconds | Soapstone asks other players online for that zone's stones and fetches the ones you're missing ("12 new stones arrived for The Barrens") |
| `/soap sync` / `/soap sync now` | Zone sync status and recent results / ask again right away |
| `/soap net` | Network test tools: `selftest` and `pacetest` (one character), `status`, `ping [channel\|guild\|party\|yell\|whisper Name]`, `burst [n]`, `log` (see [Sharing — Architecture](docs/Sharing%20-%20Architecture.md)) |
| `/soap help` | All commands |

Stones are saved per account in `WTF\Account\<ACCOUNT>\SavedVariables\Soapstone.lua`
(shared by all characters on the account; each stone records which character wrote it).

## How the app maps to the addon

| App (phone) | Addon |
|---|---|
| GPS lat/long | `C_Map` world coordinates (yards, continuous per continent) |
| 1-mile listen gate | 40-yard read gate (`/soap radius`) |
| Voice note | Text (140 chars) or a Miiverse-style sketch (addons can't record audio) |
| Locked pins on map | Grey rune pins on the minimap, clamped to the rim when far |
| Press-and-hold FAB | Minimap button |

## Addon files

- `Soapstone.toc`: addon manifest, load order, SavedVariables
- `Core.lua`: saved data defaults, shared window helper, `/soap` commands, startup
- `Sketch.lua`: the 1-bit sketch grid, round brushes, gap-free lines, undo records, compact encoding
- `Stones.lua`: stone data (text or sketch), positions and distance, 1-second proximity check with near/read zones
- `Store.lua`: all stone data: stored by id with version, game and zone; tombstones, outbox, storage caps, and a spatial index for "what's near me"
- `Identity.lua`: game flavour (`forever` / `retail` / `classic`) and player identity (`Mad-Decent`, shown as "Mad Decent")
- `Cues.lua`: sound cues; picks the first built-in sound your client has, or plays a custom `.ogg`
- `Codec.lua`: stones as text for the wire, and validation of everything received
- `Net.lua`: the hidden `SoapstoneNet` channel, wire format, paced send queue, multi-part payloads, offline-peer detection, and `/soap net` test tools
- `Sync.lua`: zone sync, i.e. fetching the current zone's stones from other players
- `SketchCanvas.lua`: draws a sketch as pooled row-run rectangles; mouse drawing and undo when editable
- `DropWindow.lua`: "Leave a Soapstone" window with Write | Draw tabs and the Splatoon-style tool strip
- `WritePanel.lua`: the message box shared by the drop and edit windows
- `DrawPanel.lua`: the drawing editor (tool strip + canvas) shared by the drop and edit windows
- `ReadWindow.lua`: shows one stone's message or sketch, with the Edit countdown on your own written stones
- `EditWindow.lua`: "Edit Soapstone" dialog, for changing or deleting one of your stones (text or sketch) within its edit window
- `MinimapButton.lua`: draggable minimap button that glows while a stone is in range
- `MinimapPins.lua`: stones drawn on the minimap, with rotating-minimap support
- `Media/`: icon textures with transparent backgrounds (`Soapstone.tga` 64×64 for the button and AddOns list, `SoapstonePin.tga` 32×32 for minimap pins)

Icon source art is `art/soapstone.png`. After changing it, run `py tools/convert_icon.py` to rebuild `Media/`.

## Tests

The addon's logic is tested outside the game with Node:

```
cd tests
npm install
npm test            # everything;  node run.js sync -v  for one file, verbosely
```

`tests/run.js` syntax-checks every addon file as Lua 5.1 (what WoW runs) and
runs each `tests/*.test.lua` under [fengari](https://github.com/fengari-lua/fengari).
`tests/lib/wowsim.lua` simulates several WoW Forever players on one server
(with the measured latency and send limits) for end-to-end sync tests. The
**Tests** GitHub Action runs the suite on every push to `main` and every
pull request.

## Releasing

Versions follow [Semantic Versioning](https://semver.org/) (`MAJOR.MINOR.PATCH`).
The `## Version:` line in `Soapstone/Soapstone.toc` is the single source of truth.

1. While working, add player-facing notes under `## [Unreleased]` in `CHANGELOG.md`.
2. To release, rename that heading to `## [X.Y.Z] - YYYY-MM-DD`, add a fresh
   empty `## [Unreleased]` above it, update the compare links at the bottom,
   and set `## Version: X.Y.Z` in the `.toc`.
3. Check it: `py tools/release.py build` (writes the zip and notes to `dist/`).
4. Merge to `main`, then tag and push:
   ```
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```
   The **Release** GitHub Action checks the tag matches the `.toc` and the
   changelog, then publishes the GitHub Release with the zip attached.

## Next steps

1. **Sharing.** Zone sync is in: settle in a zone and Soapstone fetches its
   stones from other players online. Next are live drops (announcing new
   stones as they're made). See [Sharing — Architecture](docs/Sharing%20-%20Architecture.md).
   It still needs a real two-player test.
2. **In-world presence.** An on-screen arrow toward the nearest sealed stone, a
   rune glow at your feet when on the spot, and the built-in waypoint marker
   (`C_SuperTrack`) if this client has it.
3. **Shared ratings.** Appraisals and disparagements are personal for now;
   with a server they could add up across players (and, as in Dark Souls,
   tell authors when their stone was appraised).
4. **Libraries.** LibDBIcon for the minimap button, HereBeDragons-Pins for world map pins.
