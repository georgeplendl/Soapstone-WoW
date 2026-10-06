# Privacy

This page says what the Soapstone addon and the Soapstone companion app
collect, where it goes, and who can see it. The companion's installer shows
a summary of it before you install.

## The addon on its own

The Soapstone addon keeps everything in your own game files (SavedVariables).
It doesn't send anything anywhere by itself. If you turn on the old
player-to-player network (`/soap net join`, off by default), stones you
leave are also sent to other Soapstone players online in your zone.

## The companion app

The companion connects the addon to the shared Soapstone server, at
`soapstone-server.george-plendl.workers.dev` (hosted on Cloudflare Workers).

**What it sends to the server**

- The names of your characters that have played with Soapstone.
- The stones you leave: their words or drawing, where in the game you left
  them (zone and map position), and when; and your edits and deletions.
- Your appraisals and disparagements.
- Which other players' stones your characters have opened, and when.
- Stones you report.
- A random install id and secret token the companion makes up for itself
  (no account, email or password).

The server also sees your IP address, as any website does. It only keeps it
as a keyed hash, used for rate limits.

**Who can see it**

- **Everyone using Soapstone** can see the stones you leave: the words or
  drawing, your character's name, where you left it and when, plus its
  appraisal score and how many players have found it.
- **Only your own companion** gets back which stones your characters have
  opened. Other players only ever see totals.
- **The project's maintainer** can see everything on the server, to run it
  and to deal with reported stones.

**What it never collects:** your Battle.net account, email, passwords,
payment details, anything from the game's memory, or any files other than
Soapstone's own.

**On your PC** the companion keeps its settings, token and a cache of
downloaded stones in `%APPDATA%\Soapstone`.

## Keeping and deleting data

Stones stay on the server until you delete them (within 5 minutes of leaving
them, from the stone's window), or until they're removed for breaking the
rules. Daily usage counts for rate limits are kept for a short time. To have
everything from your characters removed from the server, open an issue at
<https://github.com/georgeplendl/Soapstone-WoW/issues>, or report it
privately on the repository's Security tab, and say which characters are
yours.

## Changes

If this policy changes, the new version is published here, with its history
in the repository.

*Last updated 2026-10-06.*
