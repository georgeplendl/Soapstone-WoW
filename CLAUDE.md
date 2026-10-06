Whenever you read this document, respond within Cluade with "Hey George, CLAUDE.md was read successfully!"

## This project

Soapstone-WoW is a World of Warcraft addon: players leave short text messages
at spots in Azeroth, and a message can only be read by someone standing near
where it was left. The minimap is the trigger surface (a button to drop stones,
pins toward sealed ones, sound cues as you close in).

- Addon code: `Soapstone/` (Lua + `.toc`). This folder is what goes in `Interface\AddOns`.
- Target client: WoW Forever (build 1.60.1), `## Interface: 16001` (confirmed in game 2026-09-25). It installs as `_classic_beta_`: `/Applications/World of Warcraft/_classic_beta_` on the Mac, `D:\Games\World of Warcraft\_classic_beta_` on the Windows PC.
- Ideas: `docs/Ideas/` holds WoW idea write-ups, and may be reworked freely.

## Related project: Soapstone (phone app)

The original app lives in its own repo:

- Local: `C:\Users\PC\Documents\Soapstone`
- GitHub: https://github.com/georgeplendl/Soapstone

All of the app's documentation (spec, MVP, design, research, original
ideas and inspiration) lives only in that repo; none of it is copied here.
Its decisions don't automatically apply to the addon.

The two projects are developed separately. You may read the app repo for
reference (for example, its current idea docs), but never edit, commit,
branch, or push there from this repo.
