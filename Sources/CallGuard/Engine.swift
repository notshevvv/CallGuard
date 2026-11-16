import AppKit
import CoreAudio
import Foundation

/// Real-time DSP shared with the audio thread. Plain memory: no locks, no allocation.
///
/// Two buses come in from Core Audio process taps:
///  - media: every app except call apps (YouTube, Spotify…)
///  - call:  call apps whose sound we carry (only while "Stop call ducking" is active)
/// Media gets bass, Night Mode and the sleep-timer fade; the call voice gets its own volume.
/// A stereo-linked peak limiter on the sum guarantees the output never clips.
final class DSP: @unchecked Sendable {
    // Parameters (main thread writes, audio thread reads).
    var mediaGain: Float = 1
    var callGain: Float = 1
    var mediaFade: Float = 1          // sleep timer: 1 = normal, 0 = faded out
    var bassDB: Float = 0
    var night = false
    var sampleRate: Float = 48000
    var coeffVersion: Int32 = 0
    var tapOffset = 0                 // index of the first tap buffer in the IOProc input list
    var hasCallBus = false
    // Effects (media only).
    var fxOn = false
    var fxSemitones: Float = 0
    var fxHarmony: Float = 0          // 0…1
    var fxReverb: Float = 0           // 0…1
    var fxRoom: Float = 0.6           // 0…1
    var fxWarmth: Float = 0.5         // 0…1
    var fxWidth: Float = 1            // 0…2
    let fx = Effects()
    var studioAmount: Float = 0       // 0…1 (0 = off)
    let studio = StudioMaster()
    private var studioOn = false
    private var fxActive = false

    // Audio-thread state.
    private var gM: Float = 1, gC: Float = 1, fade: Float = 1
    private var seen: Int32 = -1
    private var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
    private var zl1: Float = 0, zl2: Float = 0, zr1: Float = 0, zr2: Float = 0
    private var cEnv: Float = 0, lEnv: Float = 0
    private var limRelease: Float = 0.9999, smooth: Float = 0.999, fadeSmooth: Float = 0.99999
    private var cAtt: Float = 0.99, cRel: Float = 0.9999
    let ceiling: Float = 0.891        // −1 dBFS
    private let cThreshold: Float = 0.04, cRatio: Float = 5, cMakeup: Float = 2.8   // Night Mode: −28 dBFS, 5:1, +9 dB

    // Meters (audio thread writes, UI reads).
    var mediaPeak: Float = 0
    var callPeak: Float = 0
    var outPeak: Float = 0
    var limiting: Float = 1
    var blocks = 0
    var inputBufferCount = 0
    var firstTapChannels = 0

    private func update() {
        seen = coeffVersion
        let fs = max(sampleRate, 8000)
        limRelease = expf(-1 / (0.15 * fs))
        smooth = expf(-1 / (0.03 * fs))
        fadeSmooth = expf(-1 / (8 * fs))          // ~30 s gentle fade
        cAtt = expf(-1 / (0.005 * fs))
        cRel = expf(-1 / (0.25 * fs))
        fx.configure(sampleRate: fs, semitones: fxOn ? fxSemitones : 0, harmonyMix: fxOn ? fxHarmony : 0,
                     reverbMix: fxOn ? fxReverb : 0, room: fxRoom, warmth: fxWarmth, widthAmount: fxOn ? fxWidth : 1)
        fxActive = fx.active
        studio.configure(sampleRate: fs, amount: studioAmount)
        studioOn = studio.on
        let g = bassDB
        if abs(g) < 0.05 { b0 = 1; b1 = 0; b2 = 0; a1 = 0; a2 = 0; return }
        // RBJ low shelf, 110 Hz, slope 1.
        let A = powf(10, g / 40)
        let w0 = 2 * Float.pi * min(110, fs * 0.45) / fs
        let cw = cosf(w0), sw = sinf(w0)
        let alpha = sw / 2 * sqrtf(2)
        let sA = 2 * sqrtf(A) * alpha
        let a0 = (A + 1) + (A - 1) * cw + sA
        b0 = A * ((A + 1) - (A - 1) * cw + sA) / a0
        b1 = 2 * A * ((A - 1) - (A + 1) * cw) / a0
        b2 = A * ((A + 1) - (A - 1) * cw - sA) / a0
        a1 = -2 * ((A - 1) + (A + 1) * cw) / a0
        a2 = ((A + 1) + (A - 1) * cw - sA) / a0
    }

    @inline(__always)
    private static func buffer(_ l: UnsafeMutableAudioBufferListPointer, _ i: Int) -> (UnsafeMutablePointer<Float>, Int, Int)? {
        guard i < l.count, let p = l[i].mData?.assumingMemoryBound(to: Float.self) else { return nil }
        let ch = Int(max(l[i].mNumberChannels, 1))
        return (p, ch, Int(l[i].mDataByteSize) / (4 * ch))
    }

    func process(input: UnsafeMutableAudioBufferListPointer, output: UnsafeMutableAudioBufferListPointer) {
        if seen != coeffVersion { update() }
        blocks &+= 1
        inputBufferCount = input.count
        guard let m = Self.buffer(input, tapOffset) else {
            for b in output { if let p = b.mData { memset(p, 0, Int(b.mDataByteSize)) } }
            return
        }
        firstTapChannels = m.1
        let c = hasCallBus ? Self.buffer(input, tapOffset + 1) : nil
        var frames = m.2
        if let c { frames = min(frames, c.2) }
        for b in output { frames = min(frames, Int(b.mDataByteSize) / (4 * Int(max(b.mNumberChannels, 1)))) }

        let tM = mediaGain, tC = callGain, tF = mediaFade, doNight = night
        var pkM: Float = 0, pkC: Float = 0, pkO: Float = 0, minG: Float = 1
        for i in 0..<frames {
            gM = tM + (gM - tM) * smooth
            gC = tC + (gC - tC) * smooth
            fade = tF + (fade - tF) * fadeSmooth

            var l = m.0[i * m.1]
            var r = m.1 > 1 ? m.0[i * m.1 + 1] : l
            pkM = max(pkM, max(abs(l), abs(r)))
            // Bass shelf (transposed direct form II).
            let yl = b0 * l + zl1; zl1 = b1 * l - a1 * yl + zl2; zl2 = b2 * l - a2 * yl
            let yr = b0 * r + zr1; zr1 = b1 * r - a1 * yr + zr2; zr2 = b2 * r - a2 * yr
            l = yl; r = yr
            // Studio Master: harmonic bass, mono low end, de-mud, presence and air.
            if studioOn { studio.process(&l, &r) }
            // Night Mode: soft compressor so sudden loud bits don't wake you.
            if doNight {
                let lv = max(abs(l), abs(r))
                cEnv = lv > cEnv ? lv + (cEnv - lv) * cAtt : lv + (cEnv - lv) * cRel
                var g = cMakeup
                if cEnv > cThreshold { g *= expf((1 - 1 / cRatio) * logf(cThreshold / cEnv)) }
                l *= g; r *= g
            }
            // Effects: Slowed / Sped up, harmony, reverb, width.
            if fxActive { fx.process(&l, &r) }
            let k = gM * fade
            l *= k; r *= k
            // Call voice, mixed in after the media chain.
            if let c {
                let cl = c.0[i * c.1]
                let cr = c.1 > 1 ? c.0[i * c.1 + 1] : cl
                pkC = max(pkC, max(abs(cl), abs(cr)))
                l += cl * gC; r += cr * gC
            }
            // Limiter: instant attack, smooth release, stereo-linked: never above the ceiling.
            let pk = max(abs(l), abs(r))
            lEnv = max(pk, lEnv * limRelease)
            let g: Float = lEnv > ceiling ? ceiling / lEnv : 1
            l *= g; r *= g
            minG = min(minG, g)
            pkO = max(pkO, max(abs(l), abs(r)))
            for b in output {
                guard let op = b.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let ch = Int(max(b.mNumberChannels, 1))
                let base = i * ch
                if ch == 1 { op[base] = (l + r) * 0.5 }
                else { op[base] = l; op[base + 1] = r; if ch > 2 { for k in 2..<ch { op[base + k] = 0 } } }
            }
        }
        if !zl1.isFinite || !zr1.isFinite || !cEnv.isFinite || !lEnv.isFinite {
            zl1 = 0; zl2 = 0; zr1 = 0; zr2 = 0; cEnv = 0; lEnv = 0
        }
        mediaPeak = pkM; callPeak = pkC; outPeak = pkO; limiting = minG
    }
}

/// The audio engine: process taps → private aggregate device → our DSP → the real output.
/// No driver. Also runs "Stop call ducking" (see Decoy.swift).
final class AudioEngine {
    private(set) var isOn = false
    private(set) var running = false
    private(set) var lastError: String?
    private(set) var outputName = ""

    var gainPercent: Double = 100 { didSet { apply() } }
    var bassDB: Double = 0 { didSet { apply() } }
    var night = false { didSet { apply() } }
    var callVolumePercent: Double = 100 { didSet { apply() } }
    /// Fallback when a call app can't be moved: extra media gain to make up for the ducking.
    var callBoostDB: Double = 10 { didSet { apply() } }
    var mediaFade: Double = 1 { didSet { apply() } }
    var fxOn = false { didSet { apply() } }
    var studioOn = false { didSet { apply() } }
    var studioAmount: Double = 70 { didSet { apply() } }  // %
    var fxSemitones: Double = 0 { didSet { apply() } }
    var fxHarmony: Double = 0 { didSet { apply() } }      // %
    var fxReverb: Double = 0 { didSet { apply() } }       // %
    var fxRoom: Double = 60 { didSet { apply() } }        // %
    var fxWarmth: Double = 50 { didSet { apply() } }      // %
    var fxWidth: Double = 100 { didSet { apply() } }      // %
    var stopDucking = false { didSet { if oldValue != stopDucking { poll(force: true) } } }

    /// Apps using a mic right now (on a call).
    private(set) var callApps: [String] = []
    /// A call app still plays on the real output (so it ducks us).
    private(set) var untouchedCall = false
    /// We are carrying the call voice (ducking dodged).
    private(set) var callViaUs = false
    let decoy = Decoy()
    private(set) var decoyNote: String?

    var onChange: (() -> Void)?
    var onEvent: ((String, String) -> Void)?    // (SF symbol, text)

    // Test hooks.
    var onlyProcesses: [AudioObjectID] = []
    var testCallProcesses: [AudioObjectID] = []
    var outputOverrideUID: String?

    let dsp = DSP()
    private var taps: [AudioObjectID] = []
    private var aggID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let listeners = Listeners()
    private var deviceListeners = Listeners()
    private var rebuildPending = false
    private var pollTimer: Timer?
    private var planKey = ""
    private var decoyRefused = false
    private var engagedAt = Date.distantPast
    private var currentOutputUID = ""
    private var currentRate: Double = 0
    /// Fallback: carry the call voice inside the media tap (no separate call bus).
    private var singleTap = false
    private var failures = 0
    private var retryAt = Date.distantPast
    private var restartPending = false
    /// Polls in a row where apps were playing but every captured sample was exactly zero.
    private var silentPolls = 0
    private var lastBlocks = 0
    /// True when macOS isn't letting CallGuard hear system audio (permission missing).
    private(set) var captureBlocked = false
    /// Real (non-zero) audio has come through the taps at least once. The decoy is only
    /// used after this, so a missing permission can never leave a call on silent speakers.
    private(set) var heardSomething = false

    func setOn(_ on: Bool) {
        guard on != isOn else { return }
        isOn = on
        if on {
            listeners.add(CA.system, CA.addr(kAudioHardwarePropertyDefaultOutputDevice)) { [weak self] in self?.scheduleRebuild() }
            listeners.add(CA.system, CA.addr(kAudioHardwarePropertyDevices)) { [weak self] in self?.scheduleRebuild() }
            start()
            if onlyProcesses.isEmpty {
                let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
                t.tolerance = 0.5
                RunLoop.main.add(t, forMode: .common)
                pollTimer = t
            }
        } else {
            listeners.removeAll()
            pollTimer?.invalidate(); pollTimer = nil
            if decoy.active { decoy.release(); onEvent?("speaker.wave.2", "Call sound back on your output") }
            stop()
        }
        onChange?()
    }

    private func apply() {
        let extra = untouchedCall ? pow(10, callBoostDB / 20) : 1
        dsp.mediaGain = Float(gainPercent / 100 * extra)
        dsp.callGain = Float(callVolumePercent / 100)
        dsp.mediaFade = Float(mediaFade)
        dsp.bassDB = Float(bassDB)
        dsp.night = night
        dsp.fxOn = fxOn
        dsp.studioAmount = studioOn ? Float(studioAmount / 100) : 0
        dsp.fxSemitones = Float(fxSemitones)
        dsp.fxHarmony = Float(fxHarmony / 100)
        dsp.fxReverb = Float(fxReverb / 100)
        dsp.fxRoom = Float(fxRoom / 100)
        dsp.fxWarmth = Float(fxWarmth / 100)
        dsp.fxWidth = Float(fxWidth / 100)
        dsp.coeffVersion &+= 1
    }

    private var targetOutput: AudioObjectID {
        outputOverrideUID.flatMap { CA.device(uid: $0) } ?? decoy.realDevice ?? CA.defaultOutput
    }

    private func scheduleRebuild() {
        guard isOn, !rebuildPending else { return }
        rebuildPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            self.rebuildPending = false
            guard self.isOn else { return }
            if self.decoy.active, self.decoy.realDevice == nil {      // earbuds went away
                self.decoy.release()
                self.onEvent?("airpods", "Earbuds disconnected: call sound back to normal")
            }
            let out = self.targetOutput
            if self.running, CA.uid(out) ?? "" == self.currentOutputUID, CA.sampleRate(out) == self.currentRate { return }
            self.stop(); self.restartSoon()
        }
    }

    private struct Plan { var callProcs: [AudioObjectID]; var captured: [AudioObjectID]; var untouched: Bool; var names: [String]; var key: String }

    /// Which processes are on a call, and which of them we carry.
    private func makePlan() -> Plan {
        if !onlyProcesses.isEmpty {
            return Plan(callProcs: testCallProcesses, captured: testCallProcesses, untouched: false, names: [], key: "test")
        }
        let me = getpid()
        var callProcs: [AudioObjectID] = [], captured: [AudioObjectID] = [], names: [String] = []
        var untouched = false
        let real = decoy.active ? decoy.realDevice : nil
        let fresh = Date().timeIntervalSince(engagedAt) < 4
        for p in CA.processObjects where CA.pid(of: p) != me && CA.isRunningInput(p) {
            callProcs.append(p)
            names.append(CA.appName(of: p))
            let outs = CA.outputDevices(of: p)
            if let real, fresh || !outs.contains(real) { captured.append(p) }
            else if !outs.isEmpty { untouched = true }
        }
        let key = "\(callProcs.sorted())|\(captured.sorted())|\(untouched)"
        return Plan(callProcs: callProcs, captured: captured, untouched: untouched, names: Array(Set(names)).sorted(), key: key)
    }

    private func fail(_ msg: String) {
        lastError = msg
        NSLog("CallGuard engine: %@", msg)
        stop()
        failures += 1
        retryAt = Date().addingTimeInterval(min(pow(2, Double(failures)), 30))
        // Never leave the call on the muted decoy without the engine carrying it.
        if decoy.active {
            decoy.release()
            onEvent?("exclamationmark.triangle", "Audio engine hiccup: call sound put back on your earbuds")
        }
        onChange?()
    }

    /// Core Audio needs a moment to tear down taps before new ones can be made.
    private func restartSoon() {
        guard !restartPending else { return }
        restartPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            self.restartPending = false
            if self.isOn, !self.running { self.start() }
        }
    }

    private func start() {
        guard !running else { return }
        lastError = nil
        let out = targetOutput
        guard out != 0, let outUID = CA.uid(out) else { return fail("No output device") }
        if CA.name(out).hasPrefix("CallGuard") { return fail("Output is CallGuard's own device") }

        let plan = makePlan()
        planKey = plan.key
        callApps = plan.names; untouchedCall = plan.untouched; callViaUs = !plan.captured.isEmpty && !singleTap
        apply()

        // 1. Taps: media = everything except us and call apps; call = the call apps we carry.
        if plan.callProcs.isEmpty { singleTap = false }
        var excluded = singleTap ? plan.callProcs.filter { !plan.captured.contains($0) } : plan.callProcs
        if let mine = CA.processObject(pid: getpid()) { excluded.append(mine) }
        let media = onlyProcesses.isEmpty
            ? CATapDescription(stereoGlobalTapButExcludeProcesses: excluded)
            : CATapDescription(stereoMixdownOfProcesses: onlyProcesses)
        var descs = [media]
        if !plan.captured.isEmpty, !singleTap { descs.append(CATapDescription(stereoMixdownOfProcesses: plan.captured)) }
        let testUnmuted = ProcessInfo.processInfo.environment["CG_UNMUTED"] != nil
        for (i, d) in descs.enumerated() {
            d.name = i == 0 ? "CallGuard media" : "CallGuard call"
            d.isPrivate = true
            d.muteBehavior = testUnmuted ? .unmuted : .mutedWhenTapped
            var t = AudioObjectID(kAudioObjectUnknown)
            let st = AudioHardwareCreateProcessTap(d, &t)
            guard st == noErr, t != kAudioObjectUnknown else {
                if i == 1 {
                    // The separate call tap failed: fall back to carrying the call in the media tap.
                    for t in taps { AudioHardwareDestroyProcessTap(t) }
                    taps.removeAll()
                    singleTap = true
                    onEvent?("arrow.triangle.merge", "Call voice carried with media (simpler mode)")
                    return start()
                }
                return fail("Could not create audio tap (\(st))")
            }
            taps.append(t)
        }

        // 2. Private aggregate device: the real output + the taps, with drift correction.
        let dict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "CallGuard Engine",
            kAudioAggregateDeviceUIDKey: "CallGuard-" + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outUID]],
            kAudioAggregateDeviceTapListKey: descs.map {
                [kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: $0.uuid.uuidString] as [String: Any]
            },
        ]
        var agg = AudioObjectID(kAudioObjectUnknown)
        var st = AudioHardwareCreateAggregateDevice(dict as CFDictionary, &agg)
        guard st == noErr, agg != kAudioObjectUnknown else { return fail("Could not create output device (\(st))") }
        aggID = agg

        dsp.sampleRate = Float(CA.sampleRate(agg) > 0 ? CA.sampleRate(agg) : CA.sampleRate(out))
        dsp.tapOffset = CA.inputStreamCount(out)      // the output device's own inputs come first
        dsp.hasCallBus = descs.count > 1
        dsp.coeffVersion &+= 1

        // 3. Audio callback.
        let dsp = self.dsp
        var pid: AudioDeviceIOProcID?
        st = AudioDeviceCreateIOProcIDWithBlock(&pid, agg, nil) { _, inData, _, outData, _ in
            dsp.process(input: UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData)),
                        output: UnsafeMutableAudioBufferListPointer(outData))
        }
        guard st == noErr, let pid else { return fail("Could not start audio (\(st))") }
        procID = pid
        st = AudioDeviceStart(agg, pid)
        guard st == noErr else {
            return fail("Allow CallGuard in System Settings → Privacy & Security → Screen & System Audio Recording")
        }

        running = true
        failures = 0
        currentOutputUID = outUID
        currentRate = CA.sampleRate(out)
        outputName = CA.name(out)
        deviceListeners = Listeners()
        deviceListeners.add(out, CA.addr(kAudioDevicePropertyNominalSampleRate)) { [weak self] in self?.scheduleRebuild() }
        deviceListeners.add(out, CA.addr(kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeOutput)) { [weak self] in self?.scheduleRebuild() }
        deviceListeners.add(out, CA.addr(kAudioDevicePropertyDeviceIsAlive)) { [weak self] in self?.scheduleRebuild() }
        onChange?()
    }

    /// Every 2 s: follow calls starting/ending and rebuild the taps if the picture changed.
    private func poll(force: Bool = false) {
        guard onlyProcesses.isEmpty else { return }
        manageDecoy()
        guard isOn else { if force { onChange?() }; return }
        let plan = makePlan()
        checkSilence()
        writeStatus()
        if decoy.active, plan.untouched, Date().timeIntervalSince(engagedAt) > 4 {
            decoy.release(); decoyRefused = true
            decoyNote = "\(plan.names.joined(separator: ", ")) didn't switch, so media gets the extra boost instead"
            onEvent?("exclamationmark.triangle", decoyNote!)
            return poll(force: true)
        }
        let changed = plan.names != callApps || plan.untouched != untouchedCall
        if running, plan.key != planKey {
            stop(); restartSoon()
        } else if !running, !restartPending, Date() >= retryAt {
            start()
        }
        if changed || force { onChange?() }
    }

    private func changedNames(_ plan: Plan) -> Bool { plan.names != callApps }

    /// Silence guard: if apps are playing but the taps deliver exact digital zeros for ~6 s,
    /// macOS is blocking capture (usually the System Audio Recording permission). Hand the
    /// call back to the earbuds at once and show where to allow it.
    private func checkSilence() {
        guard running else { silentPolls = 0; return }
        let me = getpid()
        let othersPlaying = CA.processObjects.contains { CA.pid(of: $0) != me && CA.isRunningOutput($0) }
        let advancing = dsp.blocks != lastBlocks
        lastBlocks = dsp.blocks
        let heard = advancing && (dsp.mediaPeak > 0 || dsp.callPeak > 0)
        if heard { heardSomething = true }
        if othersPlaying, !heard { silentPolls += 1 } else { silentPolls = 0; if heard { captureBlocked = false } }
        guard silentPolls >= 3 else { return }
        silentPolls = 0
        captureBlocked = true
        fail("macOS isn't letting CallGuard hear your audio. Turn CallGuard on in System Settings → Privacy & Security → Screen & System Audio Recording (under System Audio Recording Only), then reopen CallGuard.")
        retryAt = Date().addingTimeInterval(60)
        onEvent?("exclamationmark.octagon.fill", "Audio permission missing: sound sent straight to your output")
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AudioCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// A small status file for troubleshooting: ~/Library/Application Support/CallGuard/status.json
    private func writeStatus() {
        func db(_ x: Float) -> Double { x > 0 ? (20 * log10(Double(x)) * 10).rounded() / 10 : -999 }
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CallGuard")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let st: [String: Any] = [
            "time": ISO8601DateFormatter().string(from: Date()),
            "running": running, "output": outputName, "decoy": decoy.active, "singleTap": singleTap,
            "callApps": callApps, "callViaUs": callViaUs, "mediaPeakDB": db(dsp.mediaPeak), "callPeakDB": db(dsp.callPeak),
            "outPeakDB": db(dsp.outPeak), "blocks": dsp.blocks, "captureBlocked": captureBlocked, "heardSomething": heardSomething, "error": lastError ?? "",
        ]
        if let data = try? JSONSerialization.data(withJSONObject: st, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: dir.appendingPathComponent("status.json"))
        }
    }

    /// Start or end the decoy as calls come and go.
    private func manageDecoy() {
        let me = getpid()
        let onCall = CA.processObjects.contains { CA.pid(of: $0) != me && CA.isRunningInput($0) }
        if !onCall { decoyRefused = false; decoyNote = nil }
        let want = isOn && (running || restartPending) && stopDucking && onCall && !decoyRefused && !captureBlocked && heardSomething
        if want, !decoy.active {
            let real = CA.defaultOutput
            if decoy.engage(real: real) {
                engagedAt = Date(); decoyNote = nil
                onEvent?("wand.and.stars", "Ducking dodged: call moved to the muted Mac speakers")
            } else if CA.isBuiltIn(real) {
                decoyNote = "Works with earbuds or headphones (you're on the Mac speakers)"
            }
        } else if !want, decoy.active {
            decoy.release()
            onEvent?("speaker.wave.2", "Call ended: sound back to normal")
        }
    }

    func stop() {
        deviceListeners.removeAll()
        if aggID != kAudioObjectUnknown {
            if let p = procID { AudioDeviceStop(aggID, p); AudioDeviceDestroyIOProcID(aggID, p) }
            AudioHardwareDestroyAggregateDevice(aggID)
        }
        for t in taps { AudioHardwareDestroyProcessTap(t) }
        taps.removeAll()
        procID = nil; aggID = kAudioObjectUnknown
        let was = running
        running = false; currentOutputUID = ""
        if was { onChange?() }
    }

    deinit { stop() }
}
