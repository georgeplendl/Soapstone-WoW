# To Do

## Redesign the soapstone images for every state

Today there's one source image, `art/soapstone.png` (an amber crystal),
converted by `tools/convert_icon.py` into two textures:

- `Media/Soapstone.tga` (64×64): the minimap button and the AddOns list icon.
- `Media/SoapstonePin.tga` (32×32): **every** pin, on both maps.

Every state below is that same pin tinted, greyed or faded in code
(`MinimapPins.lua` `style()`, `WorldMapPins.lua` `LOOKS`). Redesign them as
images of their own so each state reads at a glance, even at 14–18 px.

### Pin states (minimap and world map)

| State | When | Drawn today as |
|---|---|---|
| **Sealed** | Someone else's stone you've never stood at | Grey (minimap); larger, full colour, glowing (world map) |
| **Sealed, far** | Sealed, beyond the minimap's edge, so it clings to the rim to point the way | Grey and fainter |
| **In reach** | Close enough to read right now (within 40 yd) | Full colour |
| **Read** | You've unlocked it before, but you're out of reach | Lighter grey (minimap); dim grey (world map) |
| **Yours** | A stone you left | Full colour (minimap); teal (world map) |
| **Appraised** | You appraised someone else's stone | Gold |
| **Disparaged** | You disparaged it; it no longer calls you over | Very faint grey |

### Effects and other icons

| Image | Used for | Today |
|---|---|---|
| **Sealed glow** | The slow pulsing halo behind sealed pins on the world map | The pin itself, blended additively and scaled up |
| **Minimap button** | Drop a stone; list nearby ones | `Soapstone.tga` on Blizzard's round button art |
| **Minimap button, glowing** | A stone is in reach | Blizzard's action-button border, tinted teal |
| **AddOns list icon** | The `.toc` `IconTexture` | Same as the minimap button |

### States worth considering (new)

- **Guided:** the stone you're being guided to ("guide me there"), so it
  stands out on the map.
- **Sketch vs written:** a small mark telling a drawing from a message
  before you get there.
- **Just unlocked:** a one-off burst when a stone opens, alongside the
  "A soapstone glows nearby" message.

### Specs

- Transparent background, power-of-two sizes: 32×32 for pins (drawn at
  12–18 px), 64×64 for the button and AddOns icon, larger for the glow.
- Shapes must stay distinct when greyed out and at minimap size: rely on
  silhouette, not just colour (sealed vs read should differ even for
  colour-blind players).
- Keep sources in `art/` and convert with `tools/convert_icon.py` into
  `Soapstone/Media/*.tga`.
