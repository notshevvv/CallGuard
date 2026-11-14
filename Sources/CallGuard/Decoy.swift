import CoreAudio
import Foundation

/// "Stop call ducking": during a call, macOS ducks other sound on the device the call app
/// plays to. So we point the system output (and with it the call app) at the MacBook
/// speakers, hardware-muted, and the booster plays everything (media + the call voice,
/// captured before ducking) on the earbuds. Volume keys keep working: changes on the decoy
/// are copied to the earbuds. Everything is put back when the call ends or on quit; if the
/// app ever crashes, the speakers stay muted (silence, never a loud surprise) and the next
/// launch restores the settings.
final class Decoy {
    private(set) var active = false
    private(set) var listenUID: String?      // the real device (earbuds)
    private(set) var decoyUID: String?
    private let listeners = Listeners()
    private let d = UserDefaults.standard
    private var mirroring = false

    static func outputVolumeElements(_ dev: AudioObjectID) -> [AudioObjectPropertyElement] {
        (0...2).map { AudioObjectPropertyElement($0) }.filter {
            CA.settable(dev, CA.addr(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, $0))
        }
    }
    static func volume(_ dev: AudioObjectID) -> Float32? {
        guard let el = outputVolumeElements(dev).first else { return nil }
        return CA.get(dev, CA.addr(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, el), Float32(0))
    }
    static func setVolume(_ dev: AudioObjectID, _ v: Float32) {
        for el in outputVolumeElements(dev) {
            CA.set(dev, CA.addr(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, el), v)
        }
    }
    static func muted(_ dev: AudioObjectID) -> Bool {
        (CA.get(dev, CA.addr(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput, 0), UInt32(0)) ?? 0) != 0
    }
    static func setMuted(_ dev: AudioObjectID, _ on: Bool) {
        CA.set(dev, CA.addr(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput, 0), UInt32(on ? 1 : 0))
    }

    /// The MacBook speakers, if the real output is something else.
    static func decoyDevice(for real: AudioObjectID) -> AudioObjectID? {
        CA.devices.first { $0 != real && CA.isBuiltIn($0) && CA.hasStreams($0, input: false) }
    }

    /// Returns false if there is no device to use as a decoy (e.g. already on the speakers).
    func engage(real: AudioObjectID) -> Bool {
        guard !active, let realUID = CA.uid(real), let decoy = Self.decoyDevice(for: real), let dUID = CA.uid(decoy) else { return false }
        // Remember how the speakers were, so we can put them back (also after a crash).
        d.set(realUID, forKey: "decoy.listen")
        d.set(dUID, forKey: "decoy.decoy")
        d.set(Self.muted(decoy), forKey: "decoy.savedMute")
        if let v = Self.volume(decoy) { d.set(v, forKey: "decoy.savedVol") }

        Self.setMuted(decoy, true)
        if let v = Self.volume(real) { Self.setVolume(decoy, v) }
        listenUID = realUID; decoyUID = dUID; active = true

        // Volume keys now move the decoy's volume: copy it to the earbuds.
        listeners.add(decoy, CA.addr(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, Self.outputVolumeElements(decoy).first ?? 0)) { [weak self] in
            guard let self, self.active, !self.mirroring, let r = self.realDevice, let v = Self.volume(decoy) else { return }
            self.mirroring = true; Self.setVolume(r, v); self.mirroring = false
        }
        // The mute key un-mutes the decoy: keep the speakers silent and mute the earbuds instead.
        listeners.add(decoy, CA.addr(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput, 0)) { [weak self] in
            guard let self, self.active, !Self.muted(decoy) else { return }
            Self.setMuted(decoy, true)
            if let r = self.realDevice { Self.setMuted(r, !Self.muted(r)) }
        }
        CA.set(CA.system, CA.addr(kAudioHardwarePropertyDefaultOutputDevice), decoy)
        NSLog("CallGuard decoy: call sound sent to muted %@, listening on %@", CA.name(decoy), CA.name(real))
        return true
    }

    var realDevice: AudioObjectID? { listenUID.flatMap { CA.device(uid: $0) } }

    func release() {
        listeners.removeAll()
        let real = d.string(forKey: "decoy.listen").flatMap { CA.device(uid: $0) }
        let decoy = d.string(forKey: "decoy.decoy").flatMap { CA.device(uid: $0) }
        if let real, CA.defaultOutput == decoy || CA.defaultOutput == 0 {
            CA.set(CA.system, CA.addr(kAudioHardwarePropertyDefaultOutputDevice), real)
        }
        if let decoy {
            if let v = d.object(forKey: "decoy.savedVol") as? Float { Self.setVolume(decoy, v) }
            Self.setMuted(decoy, d.bool(forKey: "decoy.savedMute"))
        }
        for k in ["decoy.listen", "decoy.decoy", "decoy.savedMute", "decoy.savedVol"] { d.removeObject(forKey: k) }
        if active { NSLog("CallGuard decoy: released") }
        active = false; listenUID = nil; decoyUID = nil
    }

    /// After a crash: put the speakers and the output back.
    func recoverIfNeeded() { if d.string(forKey: "decoy.decoy") != nil { release() } }
}
