# CallGuard website design system

The public site (`docs/index.html`, built from `site/template.html` by `python3 site/build_site.py`) is made of the same Liquid Glass as the app. Each feature is one pane of glass that lights up in its own colour when you reach it.

## Scene and ground
- Used at night, in bed, on a dim screen, so the site is dark.
- Ground: a slowly drifting colour field behind everything (`.field`): indigo `#4a35e0`, magenta `#c23a86`, violet `#7a35f0` and a faint ember `#ff8a3d` over night `#0d0b2e`. When Mic Lock is pressed, the magenta turns red.
- With reduced motion, the drift stops.

## Glass
- `.glass`: a white gradient (15% to 4%), `backdrop-filter: blur(26px) saturate(170%)`, a 1px `rgba(255,255,255,.16)` edge, a bright top highlight, and soft offset elevation shadows (navy, never a coloured halo).
- The pinned bars (nav rail and feature bar) use a more solid indigo glass, so text stays readable where blur isn't supported.
- A pane lights up in its feature colour when its section arrives (`.band.tuned .pane`).

## Feature colours (taken from the app)
Mic Lock `#ff453a` · No Ducking `#2b9eff` · Hi-Fi Buds `#b061ff` · Studio Master `#ffc759` · Effects `#ee55bf` · 8D `#2ed9d9` · Sleep `#6b73ff` · live/OK `#34d27b`. Each section sets `--c`. Tags, ticks, meters, the lit pane and the bar lens all read from it.

## Type
- Display: Bricolage Grotesque 800, tracking −0.03 to −0.035em; h1 44–86px, h2 36–62px.
- Reading: Onest 400/600, 17px, line-height 1.6, measure about 35em.
- Measured readings and times only: JetBrains Mono, with tabular figures.
- Text: `#f6f3ff`; secondary `#cfc8ee`; tertiary `#a39bcf`.

## Components
- Buttons: the primary is a white pill (dark ink `#140f36`); the secondary is clear glass. Both rise 2px on hover and press 1px.
- Feature bar: a pinned glass pill. A tinted glass lens slides to the section you're reading and takes that section's colour. This is the signature motion.
- Mic Lock tile: a glass tile in the hero. Pressing it turns the whole page "locked" (red tile, MIC LOCKED status, red colour field).
- Readings: big mono numbers with a one-line meaning. They sit inside a pane as plain columns split by a hairline, never as cards inside cards.
- FAQ: glass `details` rows with a rotating plus.

## Motion
- Ease: `cubic-bezier(.16,1,.3,1)`.
- Panes rise out of a 10px blur as their section arrives. The bar lens slides 0.7s. The ducking meter drops 19 dB, and the sleep timeline lights one step at a time.
- Live loops (Studio levels, the 8D orbit) run only while on screen.
- With reduced motion: no drift, no rise, no loops (8D holds a fixed position).

## Rules
- No eyebrow labels, no gradient text, no coloured glows on dark, no cards inside cards.
- Never invent proof (no reviews, download counts or press). Only the measured figures from README.md and docs/how-it-works.md.
- The FAQ and JSON-LD come from README.md through the build script. Edit the README, then rebuild.
