# Soapstone for World of Warcraft

> Leave a message somewhere in Azeroth. Only someone standing where you stood can read it.

Soapstone lets you leave short messages and little drawings at spots in the
world, like the orange soapstone messages in *Dark Souls*. A stone stays
sealed until someone walks right up to it. Then it opens, and they can read
what you left there: a warning, a tip, a joke, a view worth stopping for.

Your minimap shows stones nearby and pulls you toward the sealed ones, with
a soft sound when one is close.

Made for **WoW Forever** (currently in beta).

## Screenshots

**Leave a stone:** write a message, or draw one.

<p>
  <img src="docs/Screenshots/write.png" alt="The Leave a Soapstone window on Write: &quot;Be wary of GANK!&quot;, 16 of 140 letters" width="420">
  <img src="docs/Screenshots/draw.png" alt="The Leave a Soapstone window on Draw: a sketch saying COOL! with a smiling figure giving a thumbs up" width="420">
</p>

**Find it:** its pin on the minimap, and on the world map with how far away
it is. Open it to read, appraise or disparage it.

<p>
  <img src="docs/Screenshots/minimap.png" alt="A minimap pin's tooltip in The Barrens: &quot;Be wary of GANK!&quot; by Mad Decent, score 1" width="300">
  <img src="docs/Screenshots/world-map.png" alt="A world map pin's tooltip: Your soapstone, Mad Decent, 1 hr ago, 3850 yd to the north-west, click to guide me there" width="260">
</p>
<p>
  <img src="docs/Screenshots/read.png" alt="A stone opened: &quot;Be wary of GANK!&quot; by Mad Decent, with Edit, Appraised and Disparage buttons" width="480">
</p>

## Install

### With the companion (Windows, recommended)

The [Soapstone companion](#sharing-with-other-players) installs the addon
for you, keeps it up to date, and shares stones with other players.

1. Download the latest `Soapstone-Companion-vX.Y.Z-setup.exe` from the
   [Releases page](https://github.com/georgeplendl/Soapstone-WoW/releases).
2. Run it. It installs just for your Windows user (no admin prompt), puts
   Soapstone into your WoW Forever folder, and starts with Windows; you can
   turn that off in its tray menu.
3. Restart the game once so it picks up the new files. A soapstone button
   appears on your minimap.

> **Beta.** The companion is new, so expect rough edges. Until its
> installer is code-signed, Windows may say "Windows protected your PC":
> choose **More info**, then **Run anyway**. Each release lists the
> installer's SHA-256 checksum, so you can check your download.

### Addon only (Windows or Mac)

Without the companion the addon works on its own, but it's the companion
that brings in other players' stones and shares yours. The companion is
Windows-only for now.

1. Download the latest `Soapstone-vX.Y.Z.zip` from the
   [Releases page](https://github.com/georgeplendl/Soapstone-WoW/releases).
2. Unzip it into your game's `Interface\AddOns` folder, so you end up with
   `Interface\AddOns\Soapstone\Soapstone.toc`. For WoW Forever's beta that's
   `World of Warcraft\_classic_beta_\Interface\AddOns`.
3. Restart the game. A soapstone button appears on your minimap.

What's new in each version is in the [changelog](CHANGELOG.md).

## How to play

- **Leave a stone:** click the soapstone button on your minimap, or type
  `/soap`. Write up to 140 letters, or switch to **Draw** and sketch
  something. Press **Drop Stone** and it's left right where you stand.
- **Find stones:** pins on your minimap point to stones nearby, and you'll
  hear a soft sound when an unread one is close. The world map shows every
  stone you know of and how far away it is.
- **Read a stone:** walk up to it. Within about 40 yards it opens: the
  minimap button glows, and you can click its pin to read it. Once you've
  read a stone, come back any time to read it again.
- **Get directions:** click a stone on the world map to be guided there.
  With [TomTom](https://www.curseforge.com/wow/addons/tomtom) installed you
  get its arrow; otherwise you get the game's own map pin.
- **Appraise or disparage:** praise a stone you liked, or mark one you
  didn't. Appraised pins turn gold. Disparaged ones fade and stop calling
  you over.
- **Change your mind:** for 5 minutes after dropping a stone, you can edit
  or delete it from its window.

Each of your characters finds stones for themselves: a stone your main has
read is still sealed for your alts.

## Commands

| Command | What it does |
|---|---|
| `/soap` | Leave a stone where you stand |
| `/soap list` | Stones nearby, nearest first |
| `/soap read` | Open the nearest stone you're close enough to read |
| `/soap guide` | Point the way to the nearest sealed stone (`/soap guide off` stops) |
| `/soap sync` | Reload the UI so the companion syncs now (also: shift-click the minimap button) |
| `/soap sound` | Turn the sound cues on or off |
| `/soap button` | Show or hide the minimap button |
| `/soap help` | Every command |

## Sharing with other players

The **Soapstone companion** is a small app that sits in your system tray
next to WoW and shares stones with everyone through a shared database:
stones other players left show up when you log in, along with their
drawings, and yours reach them the same way. It also installs and updates
the addon for you, so you only install one thing (see [Install](#install)).
It runs on Windows only for now.

It only reads and writes Soapstone's own files, the way the WeakAuras
Companion does, and never touches the game itself. Because WoW only loads
files when you log in or reload, new stones arrive at your next login or
`/reload`. While WoW is running, the companion checks for new stones every
3 minutes. Shift-click the minimap button (or type `/soap sync`) to reload
right away: the companion shares your new stones within seconds, and you
get every stone it has fetched so far.

What the companion sends, and who can see it, is in the
[privacy policy](PRIVACY.md). To uninstall it, use Windows Settings >
Apps > Soapstone; that also removes it from Windows startup.

## Credits

Inspired by the soapstone messages of *Dark Souls*, and spun off from
[Soapstone](https://github.com/georgeplendl/Soapstone), a phone app for
leaving voice messages at real-world places.

Want to build or change Soapstone? See the
[developer notes](docs/Development.md).

## Code signing policy

Free code signing provided by [SignPath.io](https://about.signpath.io/),
certificate by [SignPath Foundation](https://signpath.org/).

- **Committers and reviewers:** [George Plendl](https://github.com/georgeplendl)
- **Approvers:** [George Plendl](https://github.com/georgeplendl)

The companion's Windows installer is built from this repository's source by
GitHub Actions ([`companion-release.yml`](.github/workflows/companion-release.yml))
and signed only after the maintainer approves each release. Signing is
still being set up, so installers up to v0.2.2 are not signed yet.

**Privacy policy:** the companion sends the Soapstone server your
characters' names, the stones you leave and change, your appraisals and
reports, and which stones your characters have opened; the installer shows
this before you install. See
the full [privacy policy](PRIVACY.md). The addon on its own sends nothing,
unless you turn on its older player-to-player network (`/soap net join`,
off by default).

## Support

Soapstone is free. If you enjoy it, you can buy me a coffee:

<a href="https://www.buymeacoffee.com/georgeplendl"><img src="https://img.buymeacoffee.com/button-api/?text=Buy%20me%20a%20coffee&emoji=&slug=georgeplendl&button_colour=FFDD00&font_colour=000000&font_family=Inter&outline_colour=000000&coffee_colour=ffffff" alt="Buy me a coffee" height="45"></a>
