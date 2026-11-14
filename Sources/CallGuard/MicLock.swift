import CoreAudio
import Foundation

/// Mic Lock: hardware-mutes every microphone on the Mac and keeps it muted.
/// Muting at the device level means no app (WhatsApp included) receives any sound,
/// whatever its own mute button says. Tested: a muted device delivers exact digital zeros.
final class MicLock {
    private(set) var isOn = false
    private(set) var blockedUnmutes = 0
    private(set) var unmutableDevices: [String] = []
    var onChange: (() -> Void)?
    /// Called with the device name each time something un-mutes a locked mic and we re-mute it.
    var onBlocked: ((String) -> Void)?
    /// Push-to-talk: while true the locked mics are open; on release they are muted again.
    private(set) var talkThrough = false
    /// Test hook: only manage these device UIDs (nil = every mic).
    var onlyUIDs: Set<String>?

    private let listeners = Listeners()
    private var deviceListeners = Listeners()
    private var timer: Timer?
    private var watched: [AudioObjectID] = []
    private let d = UserDefaults.standard
    private let mutedByUsKey = "micLock.mutedByUs"        // device UIDs we muted (restore on unlock)
    private let prevDefaultKey = "micLock.prevDefaultInput" // default input we replaced, if any

    func setOn(_ on: Bool) {
        guard on != isOn else { return }
        isOn = on
        if on { engage() } else { release() }
        onChange?()
    }

    private func engage() {
        enforce()
        listeners.add(CA.system, CA.addr(kAudioHardwarePropertyDevices)) { [weak self] in self?.enforce() }
        listeners.add(CA.system, CA.addr(kAudioHardwarePropertyDefaultInputDevice)) { [weak self] in self?.enforce() }
        // Belt and braces: a cheap check every 3 s, in case a change slips past the listeners.
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.enforce() }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func release() {
        talkThrough = false
        timer?.invalidate(); timer = nil
        listeners.removeAll()
        deviceListeners.removeAll(); watched = []
        for uid in d.stringArray(forKey: mutedByUsKey) ?? [] {
            guard let dev = CA.device(uid: uid) else { continue }
            for el in CA.inputMuteElements(dev) { CA.setInputMuted(dev, el, false) }
        }
        d.removeObject(forKey: mutedByUsKey)
        if let prev = d.string(forKey: prevDefaultKey), let dev = CA.device(uid: prev) { CA.setDefaultInput(dev) }
        d.removeObject(forKey: prevDefaultKey)
        blockedUnmutes = 0
        unmutableDevices = []
    }

    /// Mute every input device; re-mute anything that got unmuted; make sure the default
    /// input is a device we can mute.
    private func enforce() {
        guard isOn, !talkThrough else { return }
        var mutedByUs = Set(d.stringArray(forKey: mutedByUsKey) ?? [])
        var cannot: [String] = []
        var muteable: [AudioObjectID] = []
        let inputs = CA.devices.filter { CA.hasStreams($0, input: true) && !CA.isAggregateOrVirtual($0)
            && (onlyUIDs == nil || onlyUIDs!.contains(CA.uid($0) ?? "")) }

        let rebuild = inputs != watched
        if rebuild { deviceListeners.removeAll(); watched = inputs }
        let fresh = Listeners()
        var changed = false
        for dev in inputs {
            let els = CA.inputMuteElements(dev)
            guard !els.isEmpty, let uid = CA.uid(dev) else { cannot.append(CA.name(dev)); continue }
            muteable.append(dev)
            for el in els where !CA.inputMuted(dev, el) {
                if mutedByUs.contains(uid) { blockedUnmutes += 1; onBlocked?(CA.name(dev)) }   // something un-muted it: put it back
                CA.setInputMuted(dev, el, true)
                mutedByUs.insert(uid); changed = true
                NSLog("CallGuard: muted %@ (element %u)", CA.name(dev), el)
            }
            for el in els where rebuild {
                fresh.add(dev, CA.addr(kAudioDevicePropertyMute, kAudioObjectPropertyScopeInput, el)) { [weak self] in
                    self?.enforce()
                }
            }
        }
        if rebuild { deviceListeners = fresh }
        d.set(Array(mutedByUs), forKey: mutedByUsKey)

        // If the current default mic can't be muted (e.g. iPhone Continuity mic), move the
        // default to one that can, so apps that follow the default get silence.
        let def = CA.defaultInput
        if onlyUIDs == nil, def != 0, !muteable.contains(def), let safe = muteable.first(where: CA.isBuiltIn) ?? muteable.first {
            if d.string(forKey: prevDefaultKey) == nil, let u = CA.uid(def) { d.set(u, forKey: prevDefaultKey) }
            CA.setDefaultInput(safe); changed = true
            NSLog("CallGuard: default input moved from %@ to %@ (cannot mute it)", CA.name(def), CA.name(safe))
        }
        if cannot != unmutableDevices { unmutableDevices = cannot; changed = true }
        if changed { onChange?() }
    }

    /// True when every input device that exists right now is muted.
    var allMuted: Bool {
        CA.devices.filter { CA.hasStreams($0, input: true) && !CA.isAggregateOrVirtual($0) }.allSatisfy { dev in
            let els = CA.inputMuteElements(dev)
            return !els.isEmpty && els.allSatisfy { CA.inputMuted(dev, $0) }
        }
    }

    func setTalkThrough(_ on: Bool) {
        guard isOn, on != talkThrough else { return }
        talkThrough = on
        if on {
            for uid in d.stringArray(forKey: mutedByUsKey) ?? [] {
                guard let dev = CA.device(uid: uid) else { continue }
                for el in CA.inputMuteElements(dev) { CA.setInputMuted(dev, el, false) }
            }
        } else {
            enforce()
        }
        onChange?()
    }

    /// Re-apply after a relaunch (e.g. the app was restarted while the lock was on).
    func restore(wasOn: Bool) { if wasOn { setOn(true) } }
}

/// Hi-Fi earbuds: stops Bluetooth earbuds from dropping into the muffled "headset" (call) mode.
/// Earbuds switch to that mode whenever an app records from the earbud mic. Keeping the
/// Mac's own mic as the system input keeps the earbuds in stereo high-quality mode.
final class HiFiGuard {
    private(set) var isOn = false
    var onChange: (() -> Void)?
    private let listeners = Listeners()
    private let d = UserDefaults.standard
    private let prevKey = "hifi.prevDefaultInput"

    func setOn(_ on: Bool) {
        guard on != isOn else { return }
        isOn = on
        if on {
            enforce()
            listeners.add(CA.system, CA.addr(kAudioHardwarePropertyDefaultInputDevice)) { [weak self] in self?.enforce() }
            listeners.add(CA.system, CA.addr(kAudioHardwarePropertyDevices)) { [weak self] in self?.enforce() }
        } else {
            listeners.removeAll()
            if let prev = d.string(forKey: prevKey), let dev = CA.device(uid: prev) { CA.setDefaultInput(dev) }
            d.removeObject(forKey: prevKey)
        }
        onChange?()
    }

    private func enforce() {
        guard isOn else { return }
        let def = CA.defaultInput
        guard def != 0, CA.isBluetooth(def) else { return }
        guard let mac = CA.devices.first(where: { CA.isBuiltIn($0) && CA.hasStreams($0, input: true) }) else { return }
        if let u = CA.uid(def) { d.set(u, forKey: prevKey) }
        CA.setDefaultInput(mac)
        NSLog("CallGuard: input moved from %@ to %@ to keep earbuds in hi-fi", CA.name(def), CA.name(mac))
        onChange?()
    }

    /// Bluetooth outputs currently in the low-quality call mode (16 kHz or less).
    var muffledOutputs: [String] {
        CA.devices.filter { CA.isBluetooth($0) && CA.hasStreams($0, input: false) && CA.sampleRate($0) > 0 && CA.sampleRate($0) <= 24000 }
            .map(CA.name)
    }
}
