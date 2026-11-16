import AppKit
import ServiceManagement
import SwiftUI

struct LogEntry: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let symbol: String
    let text: String
}

/// Everything the panel shows, and every switch it flips. One shared instance.
@MainActor
final class AppState: ObservableObject {
    let mic = MicLock()
    let hifi = HiFiGuard()
    let engine = AudioEngine()
    let calls = CallMonitor()
    private(set) var hotkeys: Hotkeys?
    private let d = UserDefaults.standard
    let isDemo: Bool
    var onStatusChange: (() -> Void)?

    // MARK: switches (saved)
    @Published var micLocked = false { didSet { guard !isDemo, oldValue != micLocked else { return }
        mic.setOn(micLocked); d.set(micLocked, forKey: "micLock.on")
        log(micLocked ? "mic.slash.fill" : "mic.fill", micLocked ? "Mic locked" : "Mic unlocked"); changed() } }
    @Published var stopDucking = true { didSet { guard !isDemo else { return }
        d.set(stopDucking, forKey: "duck.on"); syncEngine() } }
    @Published var hifiOn = false { didSet { guard !isDemo else { return }
        hifi.setOn(hifiOn); d.set(hifiOn, forKey: "hifi.on"); changed() } }
    @Published var boostOn = false { didSet { guard !isDemo else { return }
        d.set(boostOn, forKey: "boost.on"); syncEngine() } }
    @Published var gain: Double = 150 { didSet { guard !isDemo else { return }
        d.set(gain, forKey: "boost.gain"); syncEngine() } }
    @Published var bass: Double = 6 { didSet { guard !isDemo else { return }
        d.set(bass, forKey: "boost.bass"); syncEngine() } }
    @Published var night = false { didSet { guard !isDemo else { return }
        d.set(night, forKey: "night.on"); syncEngine() } }
    @Published var callVolume: Double = 100 { didSet { guard !isDemo else { return }
        d.set(callVolume, forKey: "call.volume"); syncEngine() } }
    // MARK: Studio Master (saved)
    @Published var studioOn = false { didSet { guard !isDemo else { return }; d.set(studioOn, forKey: "studio.on"); syncEngine()
        if oldValue != studioOn { log("sparkles", studioOn ? "Studio Master on" : "Studio Master off") } } }
    @Published var studioAmount: Double = 70 { didSet { guard !isDemo else { return }; d.set(studioAmount, forKey: "studio.amount"); syncEngine() } }

    // MARK: 8D audio (saved)
    @Published var eightDOn = false { didSet { guard !isDemo else { return }; d.set(eightDOn, forKey: "8d.on"); syncEngine()
        if oldValue != eightDOn { log("arrow.triangle.2.circlepath", eightDOn ? "8D audio on" : "8D audio off") } } }
    @Published var eightDSpeed: Double = 50 { didSet { guard !isDemo else { return }; d.set(eightDSpeed, forKey: "8d.speed"); syncEngine() } }   // 0 slow … 100 fast
    /// Seconds per full circle: slow 18 s … fast 5 s.
    var eightDSeconds: Double { 18 - 13 * eightDSpeed / 100 }

    // MARK: effects (saved)
    @Published var fxOn = false { didSet { guard !isDemo else { return }; d.set(fxOn, forKey: "fx.on"); syncEngine() } }
    @Published var fxPitch: Double = 0 { didSet { saveFX() } }        // semitones
    @Published var fxReverb: Double = 0 { didSet { saveFX() } }       // %
    @Published var fxRoom: Double = 60 { didSet { saveFX() } }        // %
    @Published var fxHarmony: Double = 0 { didSet { saveFX() } }      // %
    @Published var fxWidth: Double = 100 { didSet { saveFX() } }      // %
    @Published var fxWarmth: Double = 50 { didSet { saveFX() } }      // %
    @Published var fxPreset = "" { didSet { guard !isDemo else { return }; d.set(fxPreset, forKey: "fx.preset") } }
    private var applyingPreset = false

    private func saveFX() {
        guard !isDemo else { return }
        for (k, v) in [("fx.pitch", fxPitch), ("fx.reverb", fxReverb), ("fx.room", fxRoom), ("fx.harmony", fxHarmony),
                       ("fx.width", fxWidth), ("fx.warmth", fxWarmth)] { d.set(v, forKey: k) }
        if !applyingPreset { fxPreset = "" }
        syncEngine()
    }

    struct FXPreset { let name: String; let symbol: String; let pitch, reverb, room, harmony, width, warmth: Double }
    static let fxPresets: [FXPreset] = [
        FXPreset(name: "Slowed + Reverb", symbol: "tortoise.fill", pitch: -3, reverb: 40, room: 85, harmony: 0, width: 120, warmth: 70),
        FXPreset(name: "Sped Up", symbol: "hare.fill", pitch: 3, reverb: 0, room: 50, harmony: 0, width: 110, warmth: 30),
        FXPreset(name: "Ambience", symbol: "building.columns.fill", pitch: 0, reverb: 28, room: 60, harmony: 0, width: 135, warmth: 50),
        FXPreset(name: "Harmony", symbol: "music.note.list", pitch: 0, reverb: 18, room: 55, harmony: 45, width: 120, warmth: 45),
        FXPreset(name: "Dreamy", symbol: "cloud.moon.fill", pitch: -2, reverb: 55, room: 92, harmony: 22, width: 140, warmth: 75),
    ]

    func applyPreset(_ p: FXPreset) {
        applyingPreset = true
        fxPitch = p.pitch; fxReverb = p.reverb; fxRoom = p.room; fxHarmony = p.harmony; fxWidth = p.width; fxWarmth = p.warmth
        applyingPreset = false
        fxPreset = p.name
        if !fxOn { fxOn = true } else { syncEngine() }
        log(p.symbol, "Effect: \(p.name)")
    }

    @Published var callExtra: Double = 10 { didSet { guard !isDemo else { return }
        d.set(callExtra, forKey: "call.extra"); syncEngine() } }
    @Published var autoLockMinutes = 0 { didSet { guard !isDemo else { return }
        d.set(autoLockMinutes, forKey: "autolock.minutes") } }
    @Published var autoUnlock = false { didSet { guard !isDemo else { return }
        d.set(autoUnlock, forKey: "autounlock.on") } }

    // MARK: sleep timer
    @Published var sleepMinutes = 0 { didSet { guard !isDemo else { return }; startSleepTimer() } }
    @Published var sleepEndsAt: Date?
    @Published var mediaFaded = false

    // MARK: live status
    @Published var talking = false
    @Published var callApps: [String] = []
    @Published var callStart: Date?
    @Published var blockedUnmutes = 0
    @Published var unmutable: [String] = []
    @Published var muffled: [String] = []
    @Published var engineRunning = false
    @Published var engineError: String?
    @Published var ducking: DuckState = .idle
    @Published var outputName = ""
    @Published var callViaUs = false
    @Published var mediaLevel: Float = 0
    @Published var callLevel: Float = 0
    @Published var log: [LogEntry] = []
    @Published var launchAtLogin = false
    @Published var scrollToTopToken = 0
    @Published var panelOpen = false { didSet { meterTimer(panelOpen) } }

    enum DuckState: Equatable { case idle, off, dodged, fallback(String), needsHeadphones }

    private var sleepTimer: Timer?
    private var meter: Timer?
    private var housekeeping: Timer?
    private var lockedByAuto = false

    init(demo: Bool = false) {
        isDemo = demo
        if demo { return }
        micLocked = d.bool(forKey: "micLock.on")
        stopDucking = d.object(forKey: "duck.on") as? Bool ?? true
        hifiOn = d.bool(forKey: "hifi.on")
        boostOn = d.bool(forKey: "boost.on")
        gain = d.object(forKey: "boost.gain") as? Double ?? 150
        bass = d.object(forKey: "boost.bass") as? Double ?? 6
        night = d.bool(forKey: "night.on")
        callVolume = d.object(forKey: "call.volume") as? Double ?? 100
        callExtra = d.object(forKey: "call.extra") as? Double ?? 10
        fxOn = d.bool(forKey: "fx.on")
        studioOn = d.bool(forKey: "studio.on")
        eightDOn = d.bool(forKey: "8d.on")
        eightDSpeed = d.object(forKey: "8d.speed") as? Double ?? 50
        studioAmount = d.object(forKey: "studio.amount") as? Double ?? 70
        fxPitch = d.object(forKey: "fx.pitch") as? Double ?? 0
        fxReverb = d.object(forKey: "fx.reverb") as? Double ?? 0
        fxRoom = d.object(forKey: "fx.room") as? Double ?? 60
        fxHarmony = d.object(forKey: "fx.harmony") as? Double ?? 0
        fxWidth = d.object(forKey: "fx.width") as? Double ?? 100
        fxWarmth = d.object(forKey: "fx.warmth") as? Double ?? 50
        fxPreset = d.string(forKey: "fx.preset") ?? ""
        autoLockMinutes = d.integer(forKey: "autolock.minutes")
        autoUnlock = d.bool(forKey: "autounlock.on")
    }

    /// Wire everything up and apply the saved switches.
    func start() {
        guard !isDemo else { return }
        mic.onChange = { [weak self] in self?.changed() }
        mic.onBlocked = { [weak self] dev in self?.log("hand.raised.fill", "Blocked an unmute on \(dev)") }
        hifi.onChange = { [weak self] in self?.changed() }
        engine.onChange = { [weak self] in self?.changed() }
        engine.onEvent = { [weak self] sym, text in self?.log(sym, text) }
        calls.onChange = { [weak self] in self?.callsChanged() }

        engine.decoy.recoverIfNeeded()
        if micLocked { mic.setOn(true) } else { mic.clearLeftovers() }
        if hifiOn { hifi.setOn(true) }
        calls.start()
        syncEngine()

        let hk = Hotkeys()
        hk.onToggleLock = { [weak self] in self?.micLocked.toggle() }
        hk.onTalk = { [weak self] down in self?.setTalking(down) }
        hotkeys = hk

        let t = Timer(timeInterval: 15, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.checkAutoLock() } }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        housekeeping = t

        launchAtLogin = SMAppService.mainApp.status == .enabled
        log("checkmark.shield.fill", "CallGuard started")
        changed()
    }

    func shutdown() {
        guard !isDemo else { return }
        engine.setOn(false)
        mic.setOn(false)       // the saved choice stays, so the lock comes back on next launch
        hifi.setOn(false)
    }

    // MARK: engine

    var sleepActive: Bool { sleepEndsAt != nil || mediaFaded }

    func syncEngine() {
        guard !isDemo else { return }
        engine.gainPercent = boostOn ? gain : 100
        engine.bassDB = boostOn ? bass : 0
        engine.night = night
        engine.callVolumePercent = callVolume
        engine.callBoostDB = callExtra
        engine.fxOn = fxOn
        engine.studioOn = studioOn
        engine.eightDOn = eightDOn
        engine.eightDSeconds = eightDSeconds
        engine.studioAmount = studioAmount
        engine.fxSemitones = fxPitch
        engine.fxReverb = fxReverb
        engine.fxRoom = fxRoom
        engine.fxHarmony = fxHarmony
        engine.fxWidth = fxWidth
        engine.fxWarmth = fxWarmth
        engine.mediaFade = mediaFaded ? 0 : 1
        engine.stopDucking = stopDucking
        engine.setOn(stopDucking || boostOn || night || sleepActive || fxOn || studioOn || eightDOn)
        changed()
    }

    // MARK: mic

    func setTalking(_ down: Bool) {
        guard micLocked else { talking = false; return }
        mic.setTalkThrough(down)
        talking = down
        if down { log("waveform", "Push-to-talk: mic open") }
        onStatusChange?()
    }

    private func checkAutoLock() {
        guard autoLockMinutes > 0, calls.onCall, !micLocked else { return }
        if CallMonitor.idleSeconds >= Double(autoLockMinutes * 60) {
            lockedByAuto = true
            micLocked = true
            log("moon.zzz.fill", "You went quiet for \(autoLockMinutes) min on a call: mic locked")
        }
    }

    private func callsChanged() {
        let wasOn = callStart != nil
        callStart = calls.callStart
        if let app = calls.micUsers.first, !wasOn { log("phone.fill", "Call started (\(app))") }
        if wasOn, !calls.onCall {
            log("phone.down.fill", "Call ended")
            if autoUnlock, micLocked { micLocked = false; log("lock.open.fill", "Mic unlocked because the call ended") }
            lockedByAuto = false
        }
        changed()
    }

    // MARK: sleep timer

    private func startSleepTimer() {
        sleepTimer?.invalidate(); sleepTimer = nil
        if sleepMinutes == 0 {
            sleepEndsAt = nil
            if mediaFaded { mediaFaded = false; log("play.fill", "Media restored") }
        } else {
            mediaFaded = false
            let end = Date().addingTimeInterval(Double(sleepMinutes * 60))
            sleepEndsAt = end
            let t = Timer(fire: end, interval: 0, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.sleepFired() }
            }
            RunLoop.main.add(t, forMode: .common)
            sleepTimer = t
            log("moon.fill", "Sleep timer: media fades in \(sleepMinutes) min")
        }
        syncEngine()
    }

    private func sleepFired() {
        sleepEndsAt = nil
        mediaFaded = true
        log("moon.stars.fill", "Sleep timer: media faded out, call voice kept")
        syncEngine()
    }

    func restoreMedia() { sleepMinutes = 0; mediaFaded = false; syncEngine() }

    // MARK: login item

    func setLaunchAtLogin(_ on: Bool) {
        guard !isDemo else { launchAtLogin = on; return }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            log("exclamationmark.triangle", "Start at login: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: status

    func log(_ symbol: String, _ text: String) {
        log.insert(LogEntry(date: Date(), symbol: symbol, text: text), at: 0)
        if log.count > 60 { log.removeLast(log.count - 60) }
    }

    func changed() {
        guard !isDemo else { return }
        talking = mic.talkThrough
        blockedUnmutes = mic.blockedUnmutes
        unmutable = mic.unmutableDevices
        muffled = hifi.muffledOutputs
        callApps = calls.micUsers
        engineRunning = engine.running
        engineError = engine.lastError
        outputName = engine.outputName
        callViaUs = engine.callViaUs
        if !stopDucking { ducking = .off }
        else if engine.decoy.active { ducking = .dodged }
        else if let n = engine.decoyNote { ducking = n.hasPrefix("Works with") ? .needsHeadphones : .fallback(n) }
        else { ducking = .idle }
        onStatusChange?()
    }

    private func meterTimer(_ on: Bool) {
        meter?.invalidate(); meter = nil
        guard on, !isDemo else { return }
        let t = Timer(timeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let run = self.engine.running
                self.mediaLevel = run ? self.engine.dsp.mediaPeak * Float(self.engine.dsp.mediaGain) : 0
                self.callLevel = run ? self.engine.dsp.callPeak : 0
            }
        }
        RunLoop.main.add(t, forMode: .common)
        meter = t
        changed()
    }

    // MARK: demo (for screenshots)

    static func demo() -> AppState {
        let s = AppState(demo: true)
        s.micLocked = true; s.stopDucking = true; s.hifiOn = true; s.boostOn = true
        s.gain = 180; s.bass = 6; s.night = true; s.callVolume = 100
        s.studioOn = true; s.studioAmount = 70
        s.eightDOn = true; s.eightDSpeed = 50
        s.fxOn = true; s.fxPitch = -3; s.fxReverb = 40; s.fxRoom = 85; s.fxHarmony = 0; s.fxWidth = 120; s.fxPreset = "Slowed + Reverb"
        s.autoLockMinutes = 20; s.autoUnlock = true
        s.sleepMinutes = 30; s.sleepEndsAt = Date().addingTimeInterval(23 * 60 + 41)
        s.callApps = ["WhatsApp"]; s.callStart = Date().addingTimeInterval(-(2 * 3600 + 17 * 60 + 5))
        s.blockedUnmutes = 3; s.engineRunning = true; s.ducking = .dodged; s.outputName = "AirPods Pro"
        s.callViaUs = true; s.mediaLevel = 0.42; s.callLevel = 0.28; s.launchAtLogin = true
        let now = Date()
        s.log = [
            LogEntry(date: now.addingTimeInterval(-60), symbol: "hand.raised.fill", text: "Blocked an unmute on AirPods Pro"),
            LogEntry(date: now.addingTimeInterval(-1900), symbol: "moon.zzz.fill", text: "You went quiet for 20 min on a call: mic locked"),
            LogEntry(date: now.addingTimeInterval(-8200), symbol: "wand.and.stars", text: "Ducking dodged: call moved to the muted Mac speakers"),
            LogEntry(date: now.addingTimeInterval(-8225), symbol: "phone.fill", text: "Call started (WhatsApp)"),
        ]
        return s
    }
}
