# Developer notes

How Soapstone is built, tested and released. Players: see the
[README](../README.md).

Soapstone is a World of Warcraft addon spun off from
[Soapstone](https://github.com/georgeplendl/Soapstone) (local checkout:
`C:\Users\PC\Documents\Soapstone`), the location-based voice-message phone
app. The two are separate repos, developed independently. It starts from the
same idea (the orange soapstone messages in *Dark Souls*, rooted in place) and
is expected to drift away from the app as it finds what works inside WoW.

The minimap is the trigger surface: a button to drop stones, pins that pull you
toward sealed ones, and sound cues as you close in.

## Layout

- `Soapstone/`: the addon (this folder goes in `Interface\AddOns`)
- `server/`: the companion app's server (Cloudflare Worker + database); see [its README](../server/README.md)
- `companion/`: the companion tray app (Tauri: Rust plus a small HTML window); see [its README](../companion/README.md)
- `tests/`: the addon's tests (Node + fengari); see [Tests](#tests)
- `tools/`: release, CurseForge upload, icon conversion and build-info scripts
- `art/`: icon source art (`soapstone.png`, plus `soapstone-hires.svg` and 512/1024 px renders for store pages)
- `docs/Ideas/`: WoW idea write-ups
- `docs/Sharing - Architecture.md`: the older player-to-player network (opt-in since 0.3.1)
- `docs/To Do.md`: the to-do list
- The phone app's docs (spec, research, original ideas) live in its own repo: [georgeplendl/Soapstone](https://github.com/georgeplendl/Soapstone)

## Download

Players get the addon from
[CurseForge](https://www.curseforge.com/wow/addons/soapstone) (best through
the CurseForge app, which keeps it updated) and the companion for sharing
(which also installs the addon if it's missing). The companion and the zip are
on the [Releases page](https://github.com/georgeplendl/Soapstone-WoW/releases),
and the [README](../README.md#install) has the steps. Addon releases are
tagged `vX.Y.Z`, companion releases `companion-vX.Y.Z`. `/soap version`
shows what's installed. Full history is in [CHANGELOG.md](../CHANGELOG.md).

## Install (dev loop)

Target client: WoW Forever (build `1.60.1.70009`), which installs as
`_classic_beta_`: `D:\Games\World of Warcraft\_classic_beta_` on the
Windows PC, `/Applications/World of Warcraft/_classic_beta_` on the Mac.

Link the addon folder into AddOns so edits are live after `/reload`
(replace `<repo>` with your clone). On Windows, from an **admin** Command Prompt:

```
mklink /J "D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns\Soapstone" "<repo>\Soapstone"
```

On the Mac:

```
ln -s "<repo>/Soapstone" "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/Soapstone"
```

The companion never replaces a linked addon folder, so it's safe to run it
alongside a dev checkout.

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

## Everything you can do

The full reference; players get the short version in the [README](../README.md).

| Action | What happens |
|---|---|
| Left-click minimap button (or `/soap`) | "Leave a Soapstone" window: **Write** / **Draw** buttons at the top pick a message or a sketch |
| Draw | 160×60 black-and-white canvas at 3×; 3 pen and 3 eraser sizes; left-drag draws, right-drag erases; Undo, Clear (undoable) |
| Right-click minimap button (or `/soap list`) | Nearest 10 stones with distance + compass direction |
| Click a readable minimap pin (or `/soap read`) | Opens the stone: message, or sketch at 3×. It closes if you walk out of range |
| Open one of your own stones (written or drawn) within 5 min of posting it | **Edit (m:ss)** button counts down; opens "Edit Soapstone" (the message box, or the drawing editor for a sketch) to change it (marked "(edited)") or delete it (with confirmation). The clock pauses while the editor is open, and a saved edit restarts the full 5 minutes |
| `/soap test` | Plants a stranger's stone or sketch 200 yd north of you — walk to it |
| Walk within 150 yd of an unread stone | Soft "somewhere close" ping + notice (re-arms when you walk away) |
| Walk within 40 yd of a stone | The button glows while in range; the first time also prints the message |
| Hover a minimap pin | Message if you're in range; "sealed" + distance if not; the score, and how many players found it |
| Open the world map | Every stone you know of. Sealed ones glow; hover for distance + direction (never the message). A line at the bottom counts what's left to find |
| Click a world map pin (or `/soap guide`) | Guide me there: TomTom's arrow if you have TomTom, else the game's map pin and in-world marker. `/soap guide off` stops |
| **Appraise** / **Disparage** on any stone | Under the message or sketch: the author (right), a rule, then Edit (left) and Appraise / Disparage (centred); the stone's appraisals show at the right of the title bar. Your own stones start appraised (score 1); Disparage withdraws that to 0, never below. On others' stones, Appraise (+1) or Disparage (−1), press again to withdraw; appraised pins turn gold, disparaged pins fade and stop triggering sound cues. The score shown is the author's appraisal plus the server's shared score (everyone else's votes, one per computer) and your vote if it hasn't uploaded yet; for stones the server hasn't seen, your characters' judgements instead |
| `/soap sound test` | Preview the "somewhere close" cue; `/soap sound <cue>` plays one (`near`, `appraise`, `disparage`, `drop`, `delete`) and names the sound; `/soap sound on\|off` toggles them |
| `/soap radius 25`, `/soap near 100` | Change the read / "somewhere close" ranges |
| `/soap version` | Shows the installed version and which build it is: `0.2.0 (branch ratings @ 16dd7e0, 2026-09-25 18:02)` in a dev checkout, `(release v0.3.0 @ …)` from a release zip |
| `/soap stats` | How many stones are stored (yours, others', test), tombstones, changes waiting for the companion, the companion's status ("synced 2 mins ago"), game and region, and the busiest zones |
| Settle in a zone for a few seconds (networking on) | Soapstone asks other players online for that zone's stones and fetches the ones you're missing ("12 new stones arrived for The Barrens") |
| `/soap sync` (or shift-click the minimap button) | Sync with the companion app: reloads the UI, so your changes upload and the latest stones load |
| `/soap net sync` / `/soap net sync now` | Zone sync between players (networking on): status and recent results / ask again right away |
| `/soap net join` / `leave` | Turn sharing with other Soapstone players on or off. **Off by default** since 0.3.1 |
| `/soap net` | Network test tools: `selftest` and `pacetest` (one character), `status`, `ping [channel\|guild\|party\|yell\|whisper Name]`, `burst [n]`, `log` (see [Sharing — Architecture](Sharing%20-%20Architecture.md)) |
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
- `BuildInfo.lua`: which build this is, for `/soap version` (git-ignored; written by the git hooks, or by the release tools in a release)
- `Core.lua`: saved data defaults, shared window helper, `/soap` commands, startup
- `Sketch.lua`: the 1-bit sketch grid, round brushes, gap-free lines, undo records, compact encoding
- `Stones.lua`: stone data (text or sketch), positions and distance, 1-second proximity check with near/read zones
- `Store.lua`: all stone data: stored by id with version, game and zone; tombstones, outbox, storage caps, and a spatial index for "what's near me"
- `Identity.lua`: game flavour (`forever` / `retail` / `classic`) and player identity (`Mad-Decent`, shown as "Mad Decent")
- `Cues.lua`: sound cues; picks the first built-in sound your client has, or plays a custom `.ogg`
- `Codec.lua`: stones as text for the wire, and validation of everything received
- `Net.lua`: the hidden `SoapstoneNet` channel, wire format, paced send queue, multi-part payloads, offline-peer detection, and `/soap net` test tools
- `Sync.lua`: zone sync, i.e. fetching the current zone's stones from other players (only with networking on)
- `Companion.lua`: reads the `SoapstoneData` helper addon the companion writes (stones, removals, upload results, unlocks, drawings), the "Companion:" status, and `/soap sync`
- `SketchCanvas.lua`: draws a sketch as pooled row-run rectangles; mouse drawing and undo when editable
- `DropWindow.lua`: "Leave a Soapstone" window with Write / Draw buttons and the Splatoon-style tool strip
- `WritePanel.lua`: the message box shared by the drop and edit windows
- `DrawPanel.lua`: the drawing editor (tool strip + canvas) shared by the drop and edit windows
- `ReadWindow.lua`: shows one stone's message or sketch, with the Edit countdown on your own written stones
- `EditWindow.lua`: "Edit Soapstone" dialog, for changing or deleting one of your stones (text or sketch) within its edit window
- `MinimapButton.lua`: draggable minimap button that glows while a stone is in range
- `MinimapPins.lua`: stones drawn on the minimap, with rotating-minimap support
- `WorldMapPins.lua` / `.xml`: stones on the world map (sealed ones glow) and the count line, through the map's own pin system
- `Guide.lua`: "guide me there" waypoints, through TomTom (an optional dependency) or the game's own waypoint
- `Media/`: icon textures with transparent backgrounds (`Soapstone.tga` 64×64 for the button and AddOns list, `SoapstonePin.tga` 32×32 for the pins on both maps)

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
pull request, along with the companion's Rust tests and the
[CurseForge checks](#curseforge).

The other parts have their own tests: `cd companion && npm test` (Rust,
`cargo test`) and `cd server && npm test` (Cloudflare's local runtime; needs
Node 22). The server's tests aren't in CI yet, so run them before deploying.

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
   It then uploads the same zip to
   [CurseForge](https://www.curseforge.com/projects/1730855) as a **beta**
   file for WoW Forever, with that version's changelog
   (`tools/curseforge.py`). If only the CurseForge upload fails, use
   **Re-run failed jobs** on the workflow run.
5. The companion carries its own copy of the addon, so after an addon
   release, tag a companion release (`companion-vX.Y.Z`) to ship it there too.
   Publish companion releases as **Latest**; addon releases never are
   (`--latest=false`). The README, the CurseForge page and
   `/soap companion` link to `releases/latest` for the companion's installer.

### CurseForge

- Project id `1730855`, in the `.toc` as `## X-Curse-Project-ID`.
- The project page's text lives in [`docs/CurseForge/`](CurseForge/) and is
  pasted in by hand: CurseForge's API has no endpoint for project pages.
  It's made from the README (`py tools/curseforge.py page`), so edit the
  README, not `description.md`; the Tests workflow checks they match.
- The upload runs only once the repo secret `CF_API_TOKEN` is set (a token
  from authors.curseforge.com > Settings > API tokens). Until then the
  Release workflow just leaves a notice.
- The game version comes from `## Interface:` (`16001` is CurseForge's
  `1.60.1`) and its id is looked up through the API. If that lookup fails or
  finds more than one, set the repo variable `CF_GAME_VERSION_IDS` to the
  right id.
- Files go up as `beta` while WoW Forever is in beta: change `RELEASE_TYPE`
  in `tools/curseforge.py` (or set `CF_RELEASE_TYPE`) at launch. At launch,
  also check whether the `Interface` number and CurseForge game version change.
- TomTom is listed as an optional dependency.
- `py tools/curseforge.py upload --dry-run` shows what would be sent.
  `py tools/curseforge.py check` (needs `CF_API_TOKEN`) checks that the
  token works and the game version resolves, without uploading. The Tests
  workflow runs both on every push and pull request (`check` only while the
  secret is set), so a revoked token or a renamed game version shows up as a
  failed **curseforge** job before release day. After replacing the token,
  re-run any Tests run to check it.

## Next steps

Sharing through the companion is live (companion 0.2.x, server deployed
2026-10-06); its plan and build order are in
[Idea - Companion App (WoW)](Ideas/Idea%20-%20Companion%20App%20(WoW).md).
Short-term chores (CurseForge, icons) are in [To Do](To%20Do.md).

1. **Tell authors when their stone was appraised**, as in Dark Souls. Shared
   scores and found counts are in (unreleased).
2. **Reporting from the game.** The server takes reports, but the addon has
   no Report button yet.
3. **Moderation page** on the server: reported stones, bans, releasing names.
4. **Trim the player-to-player network to live drops.** Remove zone sync and
   the outbox now that the companion carries stones
   ([Sharing — Architecture](Sharing%20-%20Architecture.md)).
5. **Code signing** for the companion installer (SignPath, being set up),
   then a macOS companion.
6. **In-world presence.** A rune glow at your feet when on the spot. (The
   arrow and waypoint marker are in: "guide me there", through TomTom or
   the game's own waypoint.)
7. **Libraries.** LibDBIcon for the minimap button.
