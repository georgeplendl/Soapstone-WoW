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
- **Tray icon** with a status line and Open / Check now / Quit. Closing the
  window keeps it in the tray.

Not yet: uploading and downloading stones, writing `SoapstoneData`, installing
the addon, Start with Windows. Uploads need the addon's `meta` and `pending`
(build order step 1 in the design doc).

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

It talks to `http://127.0.0.1:8787` until the server is deployed. Set
`SOAPSTONE_SERVER` to point it somewhere else; each server keeps its own
registration in `companion.json`.

## Layout

| File | Does |
|---|---|
| `src-tauri/src/lib.rs` | Tray, window, and the background thread that scans and checks in |
| `src-tauri/src/installs.rs` | Finding WoW folders (the only per-platform paths) |
| `src-tauri/src/lua.rs` | SavedVariables parser: data only, refuses code |
| `src-tauri/src/savedvars.rs` | What the companion reads from `Soapstone.lua` |
| `src-tauri/src/api.rs` | Server client and the proof of work |
| `src-tauri/src/config.rs` | `companion.json`: server URL, tokens, chosen folders |
| `src-tauri/src/files.rs` | Writing files safely (temp file, then rename) |
| `ui/` | The status window |
