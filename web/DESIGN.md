# accented.app design

## Direction

People who write in Spanish, French, Portuguese, and the rest on a Mac, and who are tired of the system hold-menu. The page should feel like **ink on warm paper**: precise, typographic, a little stubborn. The memorable thing is a living `á` — the same mark as the menu-bar item — and a strip of letterforms, not a SaaS product shot. One accent color (vermillion, the acute) on a cream field. No glass, no purple gradient, no Diarc Ember, no Fraunces.

## Tokens

| Role | Value |
|---|---|
| Paper | `#f3eee4` |
| Paper-dim | `#e7e0d2` |
| Ink | `#1c1712` |
| Ink muted | `rgba(28, 23, 18, 0.58)` |
| Ink faint | `rgba(28, 23, 18, 0.40)` |
| Line | `rgba(28, 23, 18, 0.12)` |
| Acute (accent) | `#c4452d` |
| Acute ink (on dark closer) | `#f3eee4` |
| Closer ground | `#1c1712` |
| Display | Newsreader (opsz, italic for the mark) |
| Sans | Source Sans 3 |
| Mono / keys | IBM Plex Mono |
| Max width | 1120px |
| Radius | 2px on chips, 999px on pills |
| Focus | 2px dashed ink, 4px offset |

## Layout

Header (wordmark + Download) → hero (copy left, letterform still right) → three how-it-works steps → three feature cards → dark closer → footer. Mobile: one column, CTA full-width, type steps as a stack.

## Mark

The product mark is a Newsreader italic `á` in acute. Wordmark is “accented” in the same family, lowercase, with the first `á` carrying the color. Favicon is that letter on paper. No mascot.

## Imagery

Generated with **Grok Imagine** (`image_gen`), not fal.ai. Do not generate a fake screenshot of the picker.

| File | Use | Prompt |
|---|---|---|
| `hero.webp` | Hero still, 16:9 | Large letterforms á é ñ ü ¿ painted in dense walnut ink on warm cream laid paper, letterpress impression, one vermillion acute on the á, shallow depth, studio light from the left, no device chrome, no UI, no logos, no people. |
| `og-image.png` | 1200×630 share card | Composed in code over the same paper/ink palette so the wordmark stays exact. |

Real picker still: not captured in this pass (`TODO: real picker still`). Hero is letterforms only.

## Open Design

Project: **Accented site** (`accented-site`). Artifacts: `index.html` (desktop one-pager) and `mobile.html` (390px frame). Tokens live in `styles.css`. Implemented in `web/public`.
