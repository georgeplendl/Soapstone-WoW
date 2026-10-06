# Soapstone companion

The tray app that sits next to WoW and connects the Soapstone addon to the
shared database (`../server`). Design:
[`docs/Ideas/Idea - Companion App (WoW).md`](../docs/Ideas/Idea%20-%20Companion%20App%20(WoW).md).

Built with [Tauri 2](https://tauri.app): a Rust core (`src-tauri/`) and a
plain HTML status window (`ui/`, no bundler).

## What it does so far

- **Finds WoW**: Blizzard's registry key, the folders Battle.net lists in
  `product.db`, common locations on every drive, then each game folder
  (`_retail_`, `_classic_beta_`, ...) and each `WTF\Account\<ACCOUNT>`.
- **Reads SavedVariables** (`Soapstone.lua`) with its own parser for Lua
  table literals. It never runs the file, and waits for WoW to finish
  writing it.
- **Registers with the server** on first run (proof of work, no account) and
  keeps the token in `%APPDATA%\Soapstone\companion.json`.
- **Syncs** each game type and region: uploads the addon's `pending` (only
  as characters that logged in on that account), downloads changes in the
  zones those accounts visited, and keeps everything in
  `%APPDATA%\Soapstone\cache\<flavor>-<region>.json`. It syncs when a
  SavedVariables file changes (a `/reload` or logout), and every 2 minutes.
- **Writes `SoapstoneData`** into each game folder with the addon:
  `Stones.lua` (format in `Soapstone/Companion.lua`), installed once with a
  `.toc` matching the addon's Interface number. A first install needs one
  game restart; after that `/reload` picks up each rewrite.
- **Installs and updates the addon** in each WoW Forever folder (per
  `.build.info`). The addon is built into the companion from `../Soapstone`
  at compile time, so **build releases from a clean checkout** of the tagged
  commit. Copies it didn't install are replaced only by a newer version; its
  own copies only while their files are still exactly what it wrote; linked
  folders never. Set `"manageAddon": false` in `companion.json` to turn it off.
- **Tray icon** with a status line and Open / Check now / Start with
  Windows / Quit. Closing the window keeps it in the tray. Opening the
  companion again shows the running one instead of starting a second.
- **Start with Windows** is turned on the first time a release build runs
  (once; after that it's the player's choice in the tray). Development
  builds never turn it on by themselves.

## Run it

Needs Rust (stable, MSVC on Windows), Node 22 and, on Windows, the WebView2
runtime (built into Windows 11).

```sh
cd server && npm run dev            # the local server, http://127.0.0.1:8787
cd companion && npm install
npm run dev                         # runs the tray app
npm test                            # cargo test
npm run build                       # per-user NSIS installer in src-tauri/target/release/bundle
```

One cycle without the tray, printing what happened as JSON:

```sh
src-tauri/target/debug/soapstone-companion.exe --sync-once
```

`SOAPSTONE_WOW_ONLY=<WoW folder>` limits it to one WoW folder and
`SOAPSTONE_DATA_DIR=<folder>` keeps its token and cache elsewhere, so two
test installs can play two players against a local server without touching
the real game folder.

It talks to the deployed server, `https://soapstone-server.george-plendl.workers.dev`.
Set `SOAPSTONE_SERVER=http://127.0.0.1:8787` to use a local `wrangler dev`
instead; each server keeps its own registration in `companion.json`.

## Layout

| File | Does |
|---|---|
| `src-tauri/src/lib.rs` | Tray, window, and the background thread that scans and syncs |
| `src-tauri/src/engine.rs` | One cycle: read accounts, sync each game type and region, write each folder |
| `src-tauri/src/sync.rs` | Push and pull for one game type and region, the cache, and the data file it becomes |
| `src-tauri/src/account.rs` | What the sync reads from one account's SavedVariables |
| `src-tauri/src/soapdata.rs` | Writing `Stones.lua`: base64 records only |
| `src-tauri/src/datafiles.rs` | Installing `SoapstoneData` into a game folder |
| `src-tauri/src/addon.rs` | Installing and updating the Soapstone addon itself |
| `src-tauri/src/installs.rs` | Finding WoW folders (the only per-platform paths) |
| `src-tauri/src/lua.rs` | SavedVariables parser: data only, refuses code |
| `src-tauri/src/savedvars.rs` | What the companion reads from `Soapstone.lua` |
| `src-tauri/src/api.rs` | Server client and the proof of work |
| `src-tauri/src/config.rs` | `companion.json`: server URL, tokens, chosen folders |
| `src-tauri/src/files.rs` | Writing files safely (temp file, then rename) |
| `ui/` | The status window |
