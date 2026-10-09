# CurseForge page

The text for Soapstone's
[CurseForge page](https://www.curseforge.com/wow/addons/soapstone). CurseForge
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

Don't edit `description.md` by hand: it's made from the
[README](../../README.md), so the two always say the same. Change the
README, then run `py tools/curseforge.py page` and commit both. The Tests
workflow fails if they don't match.

The README marks what's different on CurseForge with comments you only
see in its source:

- `<!-- github-only -->` ... `<!-- /github-only -->` around parts that stay
  on GitHub (the CurseForge link, developer notes, code signing policy).
- `<!-- curseforge-only ... -->` around parts only CurseForge shows (the
  Links section).

After a change, paste the new `description.md` into the CurseForge page.
