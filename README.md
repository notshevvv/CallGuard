<p align="center">
  <img src="assets/banner.png" alt="CallGuard: the all-night call companion for Mac" width="100%">
</p>

<p align="center">
  <img alt="macOS 14.4+" src="https://img.shields.io/badge/macOS-14.4%2B-000000?logo=apple&logoColor=white">
  <img alt="Apple silicon and Intel" src="https://img.shields.io/badge/Apple%20silicon%20%2B%20Intel-universal-5B3BFF">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <img alt="No drivers" src="https://img.shields.io/badge/drivers-none-2EA44F">
  <img alt="MIT License" src="https://img.shields.io/badge/license-MIT-3FA8FF">
</p>

<h3 align="center">Fall asleep on a call. Wake up with your mic still muted and your music still loud.</h3>

<p align="center">
  CallGuard is a free menu bar app for people who stay on calls for hours (long-distance couples, study calls,
  late-night gaming, all-night "sleep calls"). It fixes the three things macOS gets wrong on long calls,
  then adds the tools you wish you had at 2 a.m.
</p>

---

## The three problems

| What happens | Why | What CallGuard does |
|---|---|---|
| 🎧 You roll over, your earbud registers a tap, and **you're unmuted** on the call. | The earbud tap toggles the call app's own mute button. | **Mic Lock** mutes the microphone at the hardware level. Whatever the app's button says, it gets digital silence. Anything that un-mutes the mic is reversed within milliseconds. |
| 🔉 The moment a call starts, **YouTube and Spotify drop to a whisper.** | The call engine macOS gives call apps "ducks" all other sound on the device it plays to. Only the call app can change how much; there is no switch for you. | **No Ducking** moves the call app to a silent decoy device, where the ducking happens harmlessly, and plays everything to your earbuds from a copy taken before ducking. |
| 🫥 Your music suddenly sounds **muffled, like a phone line.** | When a call app uses the earbud mic, Bluetooth drops the earbuds into a low-quality headset mode (16 kHz, mono). | **Hi-Fi Buds** makes calls use the Mac's microphone, so your earbuds stay in stereo hi-fi. |

## Everything in one glass panel

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/panel-dark.png">
    <img src="assets/panel-light.png" width="430" alt="CallGuard's Liquid Glass panel with Mic Lock, No Ducking and Hi-Fi Buds tiles, sound boost sliders, sleep options and an activity log">
  </picture>
</p>

### Features

**For the call**
- **Mic Lock**: hardware-level mute for every microphone, including ones that connect later (AirPods, USB headsets). A red **LOCKED** sign sits in the menu bar so you always know.
- **One-click unmute**: click the red **LOCKED** icon (or the **Unmute me** button) and you're live straight away.
- **Push-to-talk while locked**: hold **⌃⌥T** to speak, let go and you're muted again. **⌃⌥M** locks and unlocks from anywhere. No Accessibility permission needed.
- **Blocked-unmute counter**: see how many times an earbud tap or an app tried to un-mute you overnight.
- **No Ducking**: media stays at full volume during calls (details in [How it works](#how-it-works)).
- **Call voice volume**: turn the other person up or down without touching your music.
- **Hi-Fi Buds**: stops Bluetooth earbuds from dropping into muffled headset mode.

**For falling asleep**
- **Sleep timer**: music and videos fade out gently after 15 min to 2 h, **and the call voice stays**.
- **Lock mic when I go quiet**: if you stop touching the keyboard and trackpad for 5–60 minutes during a call, CallGuard locks your mic for you.
- **Unlock when the call ends**, so your mic isn't left muted the next day.
- **Night Mode**: evens out sudden loud bits (ads, explosions, a laugh track) so they don't wake you.

**For your ears**
- **Volume boost to 300%** and **bass boost to +12 dB** for all Mac audio, with a limiter that never lets it clip.
- **Live level meters**, a **call timer** and an **activity log** of everything CallGuard did.

**Under the hood**
- Native SwiftUI with **Liquid Glass** on macOS 26 and later (and a matching material look on macOS 14–15). Light and dark mode.
- **No drivers, no kernel extensions, no virtual audio cable.** Built on Apple's public Core Audio process-tap API.
- **0.0% CPU when idle**, about 0.6% of one core while processing audio. Universal binary.
- **Private**: no network access, no analytics, nothing recorded or saved.

## How it works

```mermaid
flowchart LR
    subgraph apps[Your apps]
        apps1["YouTube · Spotify · games"]
        voice["WhatsApp call"]
    end
    decoy[("Mac speakers<br/>(hardware-muted decoy:<br/>ducking happens here)")]
    engine["CallGuard engine<br/>volume · bass · Night Mode<br/>sleep fade · call volume · limiter"]
    buds["🎧 Your earbuds"]
    apps1 -- "process tap<br/>(before ducking)" --> engine
    voice -- "plays to" --> decoy
    voice -. "process tap<br/>(before the mute)" .-> engine
    engine --> buds
```

1. When a call starts, CallGuard points the system output (and with it the call app) at the Mac's built-in speakers, which it **mutes at the hardware level**. The call app's ducking now lands on a device nobody is listening to.
2. **Core Audio process taps** collect every app's sound *before* it is ducked or muted, in two separate streams: media and call voice.
3. CallGuard mixes them, applies your settings, and plays the result on your earbuds through a **private aggregate device**.
4. Your **volume keys keep working**: CallGuard copies them to your earbuds. When the call ends, everything goes back exactly as it was.
5. If a call app refuses to move, CallGuard puts things back within 4 seconds and makes up for the ducking with extra gain instead.

**Measured on a MacBook Air (Apple silicon, macOS 27)**

| Check | Result |
|---|---|
| Mic Lock: what an app records while locked | exact digital silence (0 non-zero samples) |
| Input volume 0 instead of mute (what most "mute" apps do) | still −64 dBFS of room sound, which is why CallGuard uses hardware mute |
| An outside "unmute" while locked | re-muted within milliseconds, and counted |
| Ducking from the call engine, default vs. minimum setting | 19 dB difference, out of the user's control |
| No Ducking during a real WhatsApp call | media at full level ("like I'm not on a call") |
| Volume 200% | +6.0 dB |
| Bass +12 dB at 50–60 Hz | +11 dB on the low notes, 3 kHz untouched |
| Limiter: a −6 dBFS signal at 300% | held at −1.0 dBFS, no clipping |
| Night Mode | a 34 dB loud-to-quiet jump squeezed to 17 dB |
| Sleep fade | media silent, call voice unchanged |
| CPU | 0.0% idle, ~0.6% of one core while running |

The full write-up, including how to repeat these measurements yourself, is in [docs/how-it-works.md](docs/how-it-works.md).

## Install

**Download:** grab `CallGuard.zip` from [Releases](../../releases/latest), unzip it and drag **CallGuard** into **Applications**.

CallGuard isn't notarized by Apple yet, so the first launch needs one extra step:
1. Double-click CallGuard, then close the warning.
2. Open **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to CallGuard.

**Build from source** (needs Xcode 26 or later):

```bash
git clone https://github.com/notshevvv/CallGuard.git
```

```bash
cd CallGuard && ./build.sh && open dist/CallGuard.app
```

### Permissions

| Permission | When | Why |
|---|---|---|
| **Screen & System Audio Recording** (system audio only) | The first time No Ducking, the boost or the sleep timer runs | To take each app's sound before macOS ducks it. Nothing is recorded or stored. |
| None for Mic Lock | | Muting a device needs no permission. |
| None for the shortcuts | | Carbon hot keys don't need Accessibility access. |

Tick **Start at login** in the panel so CallGuard is always there when a call starts.

## Using it

| Control | What it does |
|---|---|
| Click the menu bar mic | Opens the panel. Click anywhere else or press Esc to close it. |
| Click the red **LOCKED** icon | **Unmutes you instantly** (right-click still opens the panel). |
| **Mic Lock** tile or **⌃⌥M** | Lock or unlock every microphone. |
| Hold **⌃⌥T** | Talk while locked (the icon turns green and says **LIVE**). |
| **No Ducking** tile | Keep media at full volume during calls (needs earbuds or headphones). |
| **Hi-Fi Buds** tile | Keep Bluetooth earbuds in stereo by using the Mac's mic for calls. |
| Sound boost | Volume, bass, call voice volume, Night Mode and live meters. |
| Falling asleep on a call | Sleep timer, auto-lock when you go quiet, unlock when the call ends. |
| Quit | Gives every mic back and restores your audio setup. |

## FAQ

<details>
<summary><b>Which call apps work with No Ducking?</b></summary>

Verified with **WhatsApp** for Mac. It should work with any app that follows the system output device (FaceTime, Zoom, Teams, Google Meet in a browser, Discord, Telegram…), but these haven't been tested yet. If an app doesn't move, CallGuard falls back to the extra gain automatically. Please [report what you find](../../issues/new?template=call-app-report.md).
</details>

<details>
<summary><b>Why does my Sound menu say "MacBook Speakers" during a call?</b></summary>

That's the decoy. The speakers are hardware-muted, and your audio is on your earbuds. Your volume keys still control the earbuds. When the call ends, the output switches back on its own.
</details>

<details>
<summary><b>Can CallGuard block the mic for just one app?</b></summary>

No. macOS doesn't let one app block another app's microphone without resetting privacy permissions. Mic Lock mutes the microphones themselves, so while it's on, no app can hear you. That's the only way to be sure. Push-to-talk lets you speak when you need to.
</details>

<details>
<summary><b>Does No Ducking work on the Mac's own speakers?</b></summary>

No: the speakers *are* the decoy. Use earbuds, headphones or another output. On the speakers, CallGuard uses the extra-gain fallback instead.
</details>

<details>
<summary><b>What happens if CallGuard crashes during a call?</b></summary>

The decoy speakers stay muted, so you get silence rather than a loud laptop in the middle of the night. Open CallGuard again and it restores everything.
</details>

<details>
<summary><b>Is anything recorded or sent anywhere?</b></summary>

No. CallGuard has no network code. Audio stays in memory for a few milliseconds while it is processed, then goes straight to your output.
</details>

## On Windows?

CallGuard is Mac-only, but Windows can do most of this with built-in settings: see **[WINDOWS.md](WINDOWS.md)**, which includes one-click registry files to turn call ducking off.

## Similar projects

- [Unduck Pro](https://github.com/MrRockySL/Unduck-Pro): keeps media loud on calls, with a per-app volume mixer.
- [Background Music](https://github.com/kyleneideck/BackgroundMusic): per-app volume and auto-pause (uses a virtual driver).
- [eqMac](https://github.com/bitgapp/eqMac): system-wide equalizer.

CallGuard focuses on long calls: the mic safety, sleep and earbud features above.

## Contributing

Bug reports, call-app test results and pull requests are welcome. The code is small and commented:

| File | What's in it |
|---|---|
| `Engine.swift` | Process taps, aggregate device, the real-time DSP (two buses, bass, Night Mode, fade, limiter) |
| `Decoy.swift` | The No Ducking decoy: muted speakers, volume-key mirroring, crash recovery |
| `MicLock.swift` | Hardware mute, re-mute listeners, push-to-talk, Hi-Fi Buds |
| `CallMonitor.swift` | Call detection, idle time, global shortcuts |
| `PanelView.swift`, `StatusController.swift` | The Liquid Glass panel and menu bar icon |
| `SelfTest.swift` | `--selftest-dsp` offline checks and the live test harness |

Run the offline checks with `.build/release/CallGuard --selftest-dsp`. The `tools/` folder has small command-line tools for measuring audio devices.

## License

[MIT](LICENSE). Free to use, change and share.
