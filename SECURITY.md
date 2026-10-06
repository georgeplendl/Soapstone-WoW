# Security

Soapstone is a World of Warcraft addon, a small companion app for Windows,
and a server that shares stones between players. This page says how to
report a problem, what Soapstone does to keep players safe, and the risks we
know about and haven't solved yet.

## Reporting a problem

If you find a way to break Soapstone, abuse it, or harm other players
through it, please report it privately: use **Report a vulnerability** on
this repository's [Security tab](https://github.com/georgeplendl/Soapstone-WoW/security),
rather than opening a public issue. For anything else, a normal
[issue](https://github.com/georgeplendl/Soapstone-WoW/issues) is fine.

## What Soapstone does to keep players safe

**Your computer and your game**

- The companion only reads and writes Soapstone's own files: your
  SavedVariables and the `SoapstoneData` helper addon. It never reads game
  memory, sends keystrokes, or touches the game itself, the same approach as
  the WeakAuras Companion.
- Nothing from the server ever runs as code in your game. The files the
  companion writes contain only numbers and base64 text; the addon decodes
  and checks every record and skips anything that doesn't pass, so a
  malicious server or file can at worst show wrong stones.
- WoW formatting codes (colours, links, pictures) in a stone or a name are
  always shown as plain text, so a stone can't fake a system message or
  cover your screen.
- The companion installs and updates the Soapstone addon only in WoW
  Forever folders, never over a copy you changed or a newer one you
  installed yourself, and never touches your SavedVariables.
- Each release lists the installer's SHA-256 checksum. Only download
  Soapstone from this repository's
  [Releases page](https://github.com/georgeplendl/Soapstone-WoW/releases).

**Your account and your name**

- No passwords or email. The companion registers itself with a random token
  that stays on your PC; the server stores only a hash of it.
- A character name belongs to the first companion that shares as it; nobody
  else can post, edit, delete or vote as that character.
- Where your characters have been (which stones they've opened, and when)
  is only ever sent back to your own companion. Other players see totals.
- IP addresses are only kept as keyed hashes, for rate limits.

**The shared world**

- Rate limits on every request, and daily limits on stones, edits, votes,
  finds, reports and new installs (an IPv6 network counts as one address).
- One install can share as at most 20 characters, and counts as one vote
  and one find per stone, however many characters it has.
- Stone ids belong to their author, and only that author can change a stone:
  within 5 minutes in game, and never more than 12 hours after the server
  first saw it.
- A word filter for slurs, a limit on stones in one spot and per zone, and
  dates that must make sense.
- Reports from established installs on different networks hide a stone
  until it's reviewed; brand-new installs can't hide anything.

## Known risks

These are the risks we know about and accept for now. They're listed so
players can decide for themselves, and so they don't get forgotten.

| Risk | What could happen | Where things stand |
|---|---|---|
| **Stones show where a character has been** | A stone carries its author's character name, an exact spot and the time it was left. On a PvP realm, someone could watch for fresh stones by a player and go looking for them. | Accepted for now. Possible later: hold new stones back from other players for a while, or show only rough times. |
| **The server's daily request budget** | The server runs on Cloudflare's free plan, which allows a set number of requests a day. Refused requests still count, so someone flooding the server could use the day's budget and stop sharing until midnight UTC. Stones aren't lost: they wait on players' PCs. | Every request is rate-limited and the companion syncs sparingly. Fully blocking floods needs a firewall rule in front of the server (a custom domain) or a paid plan. |
| **Name squatting** | Someone could claim a character's name before its player installs the companion, and post as them. | Claims are capped per install, and an admin can release a name. Proving who owns a character would need Blizzard sign-in, which WoW Forever doesn't offer. |
| **Unlocks are self-reported** | A modified companion could claim to have found stones it never visited, inflating "found by" counts. | Each install counts once per stone; found counts are for fun, never for anything competitive. |
| **No moderation page yet** | Reported or unpleasant stones are handled by hand on the server for now. | The moderation page is the next thing being built. |
| **The installer isn't code-signed yet** | Windows shows "Windows protected your PC", and someone could pass off a tampered copy. | Checksums are published with each release; code signing is planned. |
| **The old player-to-player network** | When turned on (it's off by default, `/soap net join`), other players can pass along stones, including ones claiming to be by someone else. | Off by default, and being trimmed down to instant drops from a stone's own author. |
