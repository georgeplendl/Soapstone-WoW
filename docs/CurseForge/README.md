# CurseForge page

The text for Soapstone's
[CurseForge page](https://www.curseforge.com/projects/1730855). CurseForge
has no API for a project's page (its API only handles files), so this is
pasted in by hand, on the project's **Description** in the
[authors console](https://authors.curseforge.com/). Each release's
changelog goes up with its file on its own (`tools/curseforge.py`).

## Summary

The one-line blurb CurseForge shows in search results:

> Leave your mark, literally. Scribble doodles and drop secret messages wherever you go, visible only to players who wander into the area.

## Description

All of [`description.md`](description.md). To paste it:

- **If the editor takes Markdown** (switch it to Markdown if it asks):
  open `description.md` on GitHub, choose **Raw**, then select all, copy
  and paste.
- **If it's a rich-text editor:** open `description.md` on GitHub (the
  normal view, not Raw), select everything from the first line to the
  last, copy and paste. The headings, lists and pictures come along.

Pictures and links use full GitHub addresses
(`raw.githubusercontent.com/.../main/...`), because the short paths the
README uses only work on GitHub. The pictures come from `main`, so merge
new screenshots before pasting.

## Keeping it up to date

It's the [README](../../README.md) rewritten for CurseForge: the companion
comes first, and the GitHub-only parts (developer notes, code signing)
are left out. When the README's player-facing parts change, change
`description.md` the same way and paste it again.
