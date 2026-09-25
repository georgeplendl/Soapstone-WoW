#idea, #soapstone, #wow, #drawing

## Stone Sketches: Miiverse-style drawings

When dropping a stone, you can draw on it instead of writing. Sketches are tiny, 1-bit black and white, and drawn with a small Splatoon-style kit. Like text, a sketch can only be seen by someone standing near where it was left.

Inspired by **Miiverse** (Nintendo's Wii U/3DS social network, 2012–2017), where you could post stylus drawings on a 320×120, 1-bit black-and-white canvas, and by **Splatoon / Splatoon 2**, which showed those posts as graffiti around Inkopolis and kept the same canvas at the Inkopolis Square mailbox after Miiverse closed. The limits are the charm: people made remarkable things inside them.

**Status:** direction agreed with George on 2026-09-25. Not built yet.

---

### Decisions (locked)

| Decision | Choice |
|---|---|
| How drawings are stored and shown | **Pixel grid (Approach A):** a fixed 1-bit grid, drawn as solid rectangles row by row |
| Canvas size | **160 × 60** (half of Miiverse, same 8:3 shape) |
| Display size | **Enlarged 2× or 3×** so nobody squints; exact scale still open, see below |
| Tools | **Full Splatoon kit:** 3 pen sizes and 3 eraser sizes |
| Moderation | **None for now.** Revisit once stones are shared between players |

---

### Creating a stone

The drop flow gets a **Write | Draw** toggle at the top:

- **Write:** today's 140-character text box
- **Draw:** the sketch canvas and tool bar

A stone is text *or* a sketch (see Open Questions). The current drop dialog is a standard Blizzard popup, which can't hold a canvas, so the drop flow becomes a small custom window built from Blizzard's own frame templates to keep the native look.

---

### The canvas

- **Grid:** 160 × 60 cells, each cell black or white. 9,600 bits = **1,200 bytes** raw.
- **Scale on screen:** each cell drawn as a block of screen pixels:

| Scale | On-screen canvas | Feel |
|---|---|---|
| 2× | 320 × 120 | Miiverse size; compact |
| 3× | 480 × 180 | Roomy; easy to place single pixels |

  Recommended starting point: **draw at 3×, read at 2×.** The editor is where precision matters; the read window can stay compact. Both could be settings.
- **Input:** mouse (a drawing tablet works too, because WoW sees it as a mouse). While a button is held, each cursor sample is joined to the previous one with a straight pixel line, so fast strokes don't leave gaps.
- **UI scale:** cells should snap to whole screen pixels so there are no seams or blurry edges at odd UI scales.

---

### Tools

| Tool | Sizes (in grid cells) | Notes |
|---|---|---|
| Pen | 1, 3, 5 | Round brush; paints black |
| Eraser | 1, 3, 5 | Round brush; paints white |
| Undo | — | Steps back one stroke (a stroke = one press-to-release) |
| Clear | — | Wipes the canvas, with confirmation |

Sizes are a starting guess and should be tuned by feel in game. At 3×, a 5-cell brush is 15 screen pixels wide.

---

### Reading a sketch

- The sketch appears in the read-the-stone window **only when you're within the read radius**, the same rule as text.
- Minimap pins and tooltips **never** show art. That keeps them cheap, and keeps the "walk there to see it" pull.

---

### How it stays light

- **Storage:** the grid is packed into bits and lightly compressed (runs of the same colour collapse well). A typical sketch should end up at a few hundred bytes in SavedVariables.
- **Rendering:** WoW addons can't paint pixels into a texture, so each row's runs of black cells are drawn as one solid rectangle. Rectangles come from a reusable pool. A normal sketch needs a few hundred; a worst-case noise pattern could need thousands, which is still fine for a window that's only open while reading.
- **Editing:** only the rows touched by the latest brush dab are redrawn.
- **Nothing runs in the background.** Art exists only while the editor or read window is open; the 1-second proximity check and minimap pins are unchanged.
- **Sharing later:** addon messages carry at most 255 bytes each and are rate-limited. A compressed 160×60 sketch fits in roughly 1–5 messages; the full Miiverse 320×120 would need about 20. This is the main reason for the smaller grid.

---

### Open Questions

1. **Scale:** 3× editor / 2× reader as recommended, or one fixed scale for both? Should players be able to change it?
2. **Text or sketch, or both?** Either-or is simpler to build first; a short caption under a sketch could come later.
3. **Undo depth:** how many strokes back? (Each step costs up to 1,200 bytes of memory while drawing.)
4. **Extras beyond the Splatoon kit?** e.g. a straight-line tool (hold Shift), invert canvas, or a fill tool. None are needed for v1.
5. **Moderation, once sharing exists:** at minimum a "hide sketches" setting and blocking an author; possibly "sketches only from guild and friends".

---

### References

- [Miiverse — Wikipedia](https://en.wikipedia.org/wiki/Miiverse)
- [Archiverse (Miiverse archive)](https://archiverse.pretendo.network/)
- [Mailbox — Inkipedia](https://splatoonwiki.org/wiki/Mailbox)
- [Inkopolis Square — Inkipedia](https://splatoonwiki.org/wiki/Inkopolis_Square)
