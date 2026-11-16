# Product

<!-- impeccable:product-schema 1 -->

## Platform

web (the marketing site). The product itself is a native macOS menu bar app.

## Stack

Static HTML/CSS/JS, no build step, hosted on GitHub Pages from `docs/` (confirmed). Small, well-known libraries from a CDN are fine.

## Users

Primary: people who stay on calls for hours on a Mac, such as long-distance couples, friends on all-night "sleep calls" and students on study calls. They often fall asleep on the call with earbuds in, and at the same time play music or video. Secondary: Mac users who want better sound (bass, 8D, slowed + reverb) for any app.

## Product Purpose

CallGuard is a free, open-source (MIT) macOS menu bar app that makes long calls safe and good-sounding. It stops macOS lowering media volume during calls, locks the microphone so an earbud tap can't unmute you, keeps Bluetooth earbuds out of muffled headset mode, and adds premium sound features to all Mac audio. It is free for good will; success means people find it, trust it enough to install it, and keep it running.

## Positioning

The only app built around the long-call situation: call safety (Mic Lock with push-to-talk, No Ducking, Hi-Fi Buds, auto-lock when you go quiet, sleep timer that keeps the call voice) together with premium sound (Studio Master, Effects, 8D Audio), all of which leave the other person's voice untouched. No drivers. Neighbouring apps either only keep media loud (Unduck Pro) or only enhance sound (Boom 3D, SoundSource, eqMac).

## Operating Context

Runs in the macOS menu bar; a click opens a Liquid Glass panel. Used during WhatsApp calls (verified), often at night, often half-asleep. Visitors arrive from GitHub, search, AI answers and social posts. They download a zip from GitHub Releases, and the app is ad-hoc/self-signed, so the first launch needs System Settings → Privacy & Security → Open Anyway.

## Capabilities and Constraints

- Features (v3.3): Mic Lock (hardware mute, re-mute in milliseconds, one-click unmute, hold ⌃⌥T to talk, ⌃⌥M toggle); No Ducking (decoy speakers + process taps; needs earbuds or headphones; verified with WhatsApp only); Hi-Fi Buds; Studio Master; Effects (Slowed + Reverb, Sped Up, Ambience, Harmony, Dreamy); 8D Audio with a manual switch; volume to 300%, bass to +12 dB, limiter at −1 dBFS; Night Mode; sleep timer; auto-lock when idle on a call; unlock when the call ends; activity log.
- macOS 14.4 or later, Apple silicon and Intel. No iPhone version (iOS doesn't allow it). Windows guide in WINDOWS.md.
- Free. No pricing, no paid tier.
- No network code, no analytics, nothing recorded.
- "Slowed" and "Sped up" shift pitch only; timing stays in sync (live audio can't be time-stretched).

## Brand Commitments

Name: CallGuard. Tagline in use: "The all-night call companion for Mac." Existing app icon: a night-sky tile with a glass shield, crescent moon and sound bars (`assets/logo.svg`); the owner is open to a refreshed logo on the website. Voice: plain, warm, honest about limits.

## Evidence on Hand

- Measured results in README.md and docs/how-it-works.md (mute = digital silence; volume 0 still leaks −64 dBFS; ducking 19 dB between min and default; DSP checks).
- The owner's own experience: "it's like I'm not on a call"; "made listening experience 10 times better" (first-hand, not a public testimonial).
- Real UI screenshots: assets/panel-dark.png, assets/panel-light.png. Banner: assets/banner.png.
- No user reviews, download counts, press or third-party testimonials exist yet. Do not invent them.

## Product Principles

1. Safety before sound: the call and the user's privacy come first; sound features never touch the other person's voice.
2. Honest about limits: say what isn't verified (other call apps) and what macOS or iOS can't do.
3. Built for half-asleep use: one click, obvious state, nothing to configure at 2 a.m.
4. Free and open, no tricks: no tracking, no upsell.

## Accessibility & Inclusion

Respect reduced motion (the site will be animated), keep text readable on dark backgrounds, keyboard-accessible controls.
