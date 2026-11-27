# Visage — brand charter

> **Direction C4 "Poussière"** (dust), chosen on 2026-11-26 among eight proposals: four directions, then
> four variants of direction C.
> Every file in `brand/` is written by the kit (`brand/kit/`): change the kit, never the files.

---

## 1. The idea

A face made of dots on a grid. The dots grow towards the edge, like the light of an outline. The right
side comes apart into dust: the moment the hologram appears or vanishes. The light is warm, a projector's,
far from the cyan nearly every hologram uses.

The mark announces what the app renders: a face of dots that forms, speaks, then comes apart.

## 2. The files

| File | Use | Background |
|---|---|---|
| `mark.svg` | The mark alone. | dark |
| `mark-light.svg` | The mark alone. | light |
| `mark-mono.svg` | One colour (black): print, engraving, stamp. | light |
| `wordmark.svg` | The name alone, in dots. | dark |
| `lockup.svg` | The mark and the name side by side. | dark |
| `lockup-light.svg` | The mark and the name side by side. | light |
| `banner.svg` | The README header: mark, name, beam, scanlines. | its own |
| `app-icon.svg` | The reference drawing of the app icon (1024). | its own |
| `menubar.svg` | The template of the menu bar icon (18 points, black). | — |
| **Animated** | | |
| `mark-animated.svg` | The mark comes apart then forms again, in a 10 s loop. | dark |
| `mark-speaking.svg` | The whole face speaking: mouth over 2.4 s, a blink every 4.6 s. | dark |
| `banner-animated.svg` | The README header, animated: the mark comes apart, a scan band sweeps down, the light flickers. | its own |

The animations are SMIL: they run in every browser and in a GitHub README, with no script.

**The app icon is not a file.** As for Awake and Siphon, building the app draws it with Core Graphics
(`brand/generate.sh --iconset <folder>`, then `iconutil -c icns`). Below 64 pixels it takes the menu bar
drawing: the full mark turns into a blot there.

**The menu bar**: the app draws the icon in code, as a template image (macOS tints it to the theme).
`menubar.svg` is only its reference.

## 3. The colours

The colours keep their French names: the code uses them (`Palette.braise`, `HoloSettings.charbon`).

| Name | Meaning | Code | Role |
|---|---|---|---|
| Charbon | charcoal | `#0E0C0A` | background |
| Braise | ember | `#FFC978` | dots, accent, the hologram's default colour |
| Or pâle | pale gold | `#FFE9C4` | text on a dark background, highlights |
| Cendre | ash | `#6E655B` | secondary text |
| Fumée | smoke | `#EDE6DC` | light surfaces |
| Brou | walnut | `#3A2612` | dots on a light background, the warmth of gradients |

Braise never goes on white: too little contrast. On a light background, the dots turn brou.

## 4. The name and the fonts

- **The name is written in dots**, drawn by the kit (a dot matrix in the spirit of the Doto typeface). No
  font travels with the files.
- **For the web and visuals**: Doto (OFL licence) for the name when it is set as text, never for running
  text; IBM Plex Sans for text; IBM Plex Mono for measurements.
- **In the app**: the system font (SF Pro, SF Mono). The app stays native and embeds no font: a choice of
  minimal dependencies, not a departure from the charter.

## 5. The rules

- **Clear space**: around the mark, at least a quarter of its width.
- **Minimum sizes**: the full mark from 48 pixels; below that, the menu bar drawing.
- **The dust dots are part of the mark**: they are not put back in place in the still version, and not
  removed.
- **Don't**: recolour it cyan or in a gradient, add an outline or a drop shadow to the mark alone, distort
  it, rearrange the dots by hand, set the name in another font.
- **Motion**: the mark does three things only. It comes apart and forms again, it breathes at rest, it
  speaks. Nothing else (no rotation, no bounce).

## 6. Motion

| Animation | Duration | Sequence |
|---|---|---|
| Come apart, form again | 10 s | whole until 1.8 s; the dots on the right leave first and arrive around 4.8 s; hold; return from 6.2 s, the rightmost come back last, around 9.2 s |
| Speak | 2.4 s (mouth), 4.6 s (eyes) | the mouth opens on an irregular rhythm, the middle more; the eyes blink on their own rhythm, so that the two never lock together |

The app takes these curves: appearing on connection, standby as dust (specification, § 7.2).

## 7. Regenerate

```shell
sh data/sources/visage/brand/generate.sh                                  # the SVG files
sh data/sources/visage/brand/generate.sh --iconset /tmp/Visage.iconset   # and the icon
```

The kit's random draws are seeded: the logo stays identical, dot for dot, to the one chosen (223 dots,
checked against the generator of the proposals).
