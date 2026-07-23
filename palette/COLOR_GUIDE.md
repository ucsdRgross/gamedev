# Reaching every colour — where each hue lives in sRGB

A practical guide to getting vivid, specific colours out of the generator. The short version:
**"maximum saturation" is not one setting.** sRGB is a lopsided box, so every hue has a
different saturation ceiling *and* reaches it at a different lightness. Ask for a colour at the
wrong lightness and the gamut mapper quietly desaturates it (this is why yellow, at a normal
mid-grey lightness, comes out olive).

## The map

Each hue's **cusp** is its most-saturated displayable point — the brightest, purest version of
that colour sRGB can show. `L` is the lightness it lives at; `max C` is how saturated it can get.

| Colour | `root_hue` | Cusp `L` | Max `C` | The pure colour |
|---|---|---|---|---|
| Red | 29 | 0.63 | 0.257 | `#FF0004` |
| Orange | 55 | 0.74 | 0.182 | `#FF8505` |
| Amber / gold | 75 | 0.81 | 0.170 | `#FFAD00` |
| Yellow | 95 | 0.88 | 0.181 | `#FED500` |
| Chartreuse | 110 | 0.96 | 0.211 | `#FDFE00` |
| Green | 142 | 0.86 | 0.291 | `#23FE00` |
| Emerald | 155 | 0.88 | 0.217 | `#00FF94` |
| Teal | 175 | 0.89 | 0.168 | `#00FED4` |
| Cyan | 195 | 0.90 | 0.154 | `#01FEFE` |
| Sky | 225 | 0.78 | 0.148 | `#00CBFF` |
| Blue | 255 | 0.63 | 0.205 | `#0185FF` |
| Indigo | 275 | 0.48 | 0.299 | `#4403FF` |
| Violet | 300 | 0.55 | 0.295 | `#9301FF` |
| Magenta | 330 | 0.70 | 0.317 | `#FF02F7` |
| Pink / rose | 350 | 0.66 | 0.274 | `#FE00A8` |

Two facts fall straight out of the `max C` column, and both are sRGB, not the tool:

- **Hues are not equally saturable.** Magenta, violet, indigo and green reach `C ≈ 0.29–0.32`;
  **cyan, teal, sky and gold top out at `≈ 0.15–0.17`.** You cannot make a neon cyan as intense
  as a neon magenta — it does not exist on screen. Don't fight it.
- **The saturated colour is not at mid-grey.** Warm→yellow→green *climb* in lightness (red peaks
  at `L 0.63`, yellow at `0.88`, chartreuse almost at white, `0.96`), while blue, indigo and
  violet peak *low* (`0.48–0.63`). A single global lightness can only ever suit some of them —
  which is the whole reason `hue_lightness_follow` exists.

## The two levers

1. **`root_hue`** picks the hue — the angle column above.
2. **Get the ramp to the cusp lightness.** A colour is only vivid if its ramp sits near its cusp
   `L`. Two ways:
   - **`hue_lightness_follow` → 1** — each hue automatically rides toward *its own* cusp. This is
     the right lever for any palette with more than one hue: yellow/green/cyan climb, blue/red
     stay put, all at once. (Default 0.5 gives a strong-but-not-maximal version; push to 1 for
     maximum.)
   - **`l_mid_base` = the cusp `L`** — manual, best when you want *one* exact colour in a
     single-hue palette (`hue_count: 1`).
3. **Chroma: ask for more than you can get.** Set **`chroma_base` 0.25–0.37** and
   **`chroma_cap` 0.37**; the gamut mapper reduces each hue to whatever it can actually hold, so
   over-asking costs nothing and guarantees you hit the ceiling. Set **`chroma_falloff_light` 0**
   (its default deliberately washes highlights out) if you want the *light* steps saturated too,
   and **`earthiness` 0** so nothing pulls toward ochre.

## Recipes

### A maximally-saturated full spectrum

```
hue_scheme: even     hue_count: 8        root_hue: 29
hue_lightness_follow: 1
chroma_base: 0.30    chroma_cap: 0.37    chroma_falloff_light: 0
earthiness: 0        l_step: 0.13        perceptual_hue_spacing: 0.5
```

Produces (foreground midtones) — note the chroma genuinely varying per hue, exactly as the map
predicts, and each hue at its own lightness:

```
#F50003 red      L0.61 C0.25     #00C5D0 cyan     L0.75 C0.13
#E3A500 gold     L0.76 C0.16     #0088EA blue     L0.62 C0.18
#9CC100 chartr.  L0.76 C0.18     #8500F5 violet   L0.53 C0.29
#00D189 emerald  L0.76 C0.17     #DE00A6 magenta  L0.60 C0.26
```

### One specific vivid colour

Single-hue palette placed exactly on the cusp — the surest way to a precise swatch:

```
hue_count: 1     root_hue: <hue from the map>     l_mid_base: <cusp L from the map>
chroma_base: 0.30     chroma_cap: 0.37     chroma_falloff_light: 0     earthiness: 0
```

Example — vivid chartreuse: `root_hue 110`, `l_mid_base 0.90`, the chroma settings above.
Example — deep vivid violet: `root_hue 300`, `l_mid_base 0.55`.

### Softer / more natural

Leave `hue_lightness_follow` at its default **0.5** and `chroma_base` around **0.15–0.18**. Hues
still reach a believable, painterly saturation without going full neon, and highlight washout
(`chroma_falloff_light` > 0) reads as sunlight. This is where the default palette and most mood
presets sit; **Neon Cyberpunk** (`follow 0.7`) and **Toxic Swamp** (`follow 0.55`) show the loud
end.

---

*The numbers here are measured from `gamutCusp()` in `src/core/gamut.js` (the same cusp lookup
`hue_lightness_follow` uses); regenerate them any time the colour maths changes.*
