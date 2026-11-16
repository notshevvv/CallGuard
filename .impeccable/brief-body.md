# Surface: CallGuard website (docs/index.html)

Scope: the public landing page on GitHub Pages. Mode: Persuade.
Audience: long-call people on a Mac (couples on sleep calls, study calls), often in bed at night with earbuds in. Job: understand in seconds that CallGuard keeps them off-air when they should be, keeps their music loud, and sounds great; then download.
Action: Download for Mac (GitHub latest release). Secondary: View on GitHub.
Proof on hand: measured results (mute = digital silence; volume 0 leaks −64 dBFS; 19 dB ducking; 0.0% CPU idle; DSP checks), real panel screenshots. No testimonials, counts or press: never invent them.
Constraints: static HTML/CSS/JS, no build step; keep SEO (title, meta, OG, JSON-LD SoftwareApplication + FAQPage, all 13 FAQ answers, llms.txt, sitemap); reduced motion respected.

## Direction contract

THESIS: The website is made of the same Liquid Glass as the app. Each feature is one pane of glass that lights up in its own colour when you reach it, the way the app's tiles light up when switched on. Refuses both the radio metaphor (rejected by the owner: "On Air doesn't make sense") and the flat headline + screenshot + equal-cards Mac page.

OWN-WORLD: a deep night colour field (indigo #0d0b2e, violet #3a1c71, magenta #a1306f, ember #ff8a3d) drifting slowly behind everything; frosted glass panes with backdrop blur, a bright specular top edge and soft offset shadows; each feature owns one glass colour taken from the app (Mic Lock red #ff453a, No Ducking blue #2b9eff, Hi-Fi violet #b061ff, Studio gold #ffc759, Effects pink #ee55bf, 8D teal #2ed9d9, Sleep periwinkle #6b73ff). Bricolage Grotesque for display, Geist for reading, JetBrains Mono only for measured readings.

STORY: the visitor presses the big Mic Lock glass tile in the hero and watches the page go "locked" (red glass, MIC LOCKED), so they get the core promise in one gesture. Scrolling, a glass lens slides along the floating feature bar and each pane lights in its colour with a working demo. Proof readings, FAQ, download.

FIRST VIEWPORT: colour field full-bleed. Glass nav rail. Left: headline "Fall asleep on the call. Your mic stays locked." with one supporting line, the Download for Mac button (bright glass, primary) and View on GitHub (clear glass). Right: the real app panel floating in a thick glass frame, tilted slightly, with the big Mic Lock tile overlapping its corner as the press-me demo. The glass feature bar sits at the bottom of the first viewport.

FORM: challenger fused with the app's own Liquid Glass (craft-making-glazier-colorfield-partition, competitive), chosen by the owner after rejecting On Air; seed:b0f58c707ba60c07.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
