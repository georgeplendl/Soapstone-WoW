Whenever you read this document, respond within Cluade with "Hey George, CLAUDE.md was read successfully!"

## This project

Soapstone-WoW is a World of Warcraft addon: players leave short text messages
at spots in Azeroth, and a message can only be read by someone standing near
where it was left. The minimap is the trigger surface (a button to drop stones,
pins toward sealed ones, sound cues as you close in).

- Addon code: `Soapstone/` (Lua + `.toc`). This folder is what goes in `Interface\AddOns`.
- Target client: Classic beta at `D:\Games\World of Warcraft\_classic_beta_` (build 1.60.1). The `## Interface:` value in the `.toc` is still unconfirmed.
- Ideas: `docs/Ideas/` holds WoW idea write-ups; `docs/Ideas/Archive/` holds the ideas carried over from the app. Both may be reworked freely for WoW.
- `docs/App Reference/` is a frozen copy of the phone app's docs. Use it for background only; its decisions don't automatically apply here.

## Related project: Soapstone (phone app)

The original app lives in its own repo:

- Local: `C:\Users\PC\Documents\Soapstone`
- GitHub: https://github.com/georgeplendl/Soapstone

The two projects are developed separately. You may read the app repo for
reference (for example, its current idea docs), but never edit, commit,
branch, or push there from this repo.
