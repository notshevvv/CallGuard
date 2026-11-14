# How CallGuard works

This page explains what CallGuard changes on your Mac, why, and how each claim in the README was measured.
Everything uses public Apple APIs. There are no drivers or kernel extensions.

## Mic Lock

**What it does:** sets `kAudioDevicePropertyMute` (input scope) on every input device and keeps it set.

**Why mute and not volume:** we recorded the built-in mic in three states:

| State | What an app receives |
|---|---|
| Normal | room sound, about −57 dBFS |
| Input volume 0 | still about −64 dBFS: you can still be heard |
| Hardware mute | exact digital zeros (0 non-zero samples out of 48,000) |

**Keeping it locked:** CallGuard listens for mute changes on each device, for devices being added (AirPods
connecting), and for the default input changing. It also re-checks every 3 seconds. When something un-mutes a
locked mic (an earbud tap handled by the call app, or the app's own button), CallGuard mutes it again within
milliseconds and logs it. If the default input is a mic that can't be muted (for example an iPhone Continuity mic),
it switches the default to one that can.

**Push-to-talk** (⌃⌥T) and the lock shortcut (⌃⌥M) are Carbon hot keys (`RegisterEventHotKey`), which work in
the background without Accessibility permission. While the key is held, the mics CallGuard muted are opened.
When you let go, they are muted again.

**Auto-lock when you go quiet** reads the time since your last keyboard or trackpad input
(`CGEventSource.secondsSinceLastEventType`), which needs no permission, and only while an app is using a mic.

## Why media gets quieter on calls (ducking)

Call apps use Apple's voice-processing audio unit for echo cancellation. While it runs, it lowers ("ducks")
all other audio on its output device. The amount is a property of that audio unit
(`kAUVoiceIOProperty_OtherAudioDuckingConfiguration`), so **only the call app can change it.**

We measured this with our own voice-processing unit (`tools/vpio.swift`) and a test tone:

| Ducking level set by the call app | Tone heard by the mic |
|---|---|
| minimum | −70.5 dB |
| default | −89.5 dB |
| mid | −105.7 dB |

Re-playing the sound through another app doesn't escape it: audio played by CallGuard on the *same* device was
ducked by exactly the same amount (−89.3 vs −89.5 dB).

## No Ducking: the decoy

The ducking applies to the device the call app plays to. So during a call CallGuard:

1. saves the built-in speakers' mute and volume, **mutes them in hardware**, and makes them the system output;
2. lets the call app follow the system output onto the muted speakers, where its ducking now lands;
3. captures every app's audio with **process taps** (`CATapDescription`, macOS 14.2+): one tap for media and one
   for the call voice. Taps hand over the sound *before* the device's ducking and mute (verified: a tap on a
   process playing to the muted speakers still reads −40.0 dBFS);
4. plays the mix on your earbuds through a **private aggregate device** (your earbuds plus both taps, with
   drift correction);
5. copies volume-key changes from the decoy to your earbuds, and turns the mute key into an earbud mute.

When the call ends (no app is using a mic), or you quit, the output goes back to your earbuds and the speakers
get their old volume and mute back. The saved state is written to disk first, so after a crash the next launch
restores it. Until then the speakers stay muted, so a crash means silence, not noise.

If the call app is still playing to your earbuds 4 seconds after the switch (it ignored the system output),
CallGuard undoes the switch and adds extra gain to media instead. Measured: +10 dB of extra gain gave +10.7 dB
at the ear while ducked.

## Hi-Fi Buds

Bluetooth earbuds have two modes: stereo music (A2DP) and a headset mode with a microphone (HFP). Headset mode is
16 kHz mono, which is what sounds muffled. It switches on whenever any app records from the earbud mic. With
Hi-Fi Buds on, CallGuard moves the system input to the Mac's built-in mic whenever a Bluetooth mic becomes the
default. Tested during a live WhatsApp call: WhatsApp followed the change and the earbuds went from 16 kHz to
44.1 kHz stereo.

## The audio engine

`Engine.swift` runs one I/O callback on the aggregate device. Per sample it applies:

1. **Media bus:** a low-shelf bass filter (RBJ, 110 Hz), Night Mode (compressor: −28 dBFS threshold, 5:1,
   +9 dB make-up, 5 ms attack, 250 ms release), volume, and the sleep-timer fade (8 s time constant).
2. **Call bus:** its own volume. Bass and Night Mode don't touch it.
3. **Limiter** on the sum: instant attack, 150 ms release, stereo-linked, ceiling −1 dBFS. Because the envelope
   is never below the current peak, the output can't exceed the ceiling.

The callback doesn't allocate or lock anything. Parameters are smoothed (30 ms) so slider moves don't click.
When nothing needs it, the engine isn't running at all: 0.0% CPU. While running it uses about 0.6% of one
Apple silicon core.

`--selftest-dsp` checks the DSP offline with synthetic signals:

```
PASS  volume 200% (+6 dB)                           got  -34.0 dB, want  -34.0
PASS  bass +12 dB at 50 Hz                          got  -28.6 dB, want  -28.5
PASS  bass leaves 3 kHz alone                       got  -40.0 dB, want  -40.0
PASS  limiter holds −1 dBFS (−6 dBFS × 300%)        got   -1.0 dB, want   -1.0
PASS  Night Mode squeezes loud vs quiet             loud−quiet spread 16.8 dB (input 34 dB)
PASS  sleep fade: media silent, call kept           got  -25.8 dB, want  -26.0
PASS  call voice 150% (+3.5 dB), media muted        got  -22.5 dB, want  -22.5
PASS  bass/volume don't touch the call bus          got  -26.0 dB, want  -26.0
ALL DSP CHECKS PASSED
```

## Repeating the measurements

The tools in [`tools/`](../tools) are single-file Swift programs. Build one with `swiftc -O tools/meter.swift -o tools/meter`.

| Tool | Use |
|---|---|
| `probe` | list audio devices (mute/volume support, sample rate) and which apps are using audio |
| `procdev` | which device each app is playing to and recording from |
| `meter <uid> <seconds> [Hz]` | record from an input; print peak/RMS and the level of one frequency |
| `tone <uid> <Hz> <dBFS> <seconds>` | play a sine directly on one output device |
| `vpio <inUID> <outUID> <seconds> [level]` | run a voice-processing unit like a call app (causes ducking) |
| `inset` / `outset` | set input mute/volume, or output mute, on one device |
| `svg2png` | render the logo and banner |

Live engine test without touching the rest of the system (tap only two test tones, play on one device):

```
CallGuard --selftest-engine <mediaPid> <callPid> BuiltInSpeakerDevice 200 0 4
```
