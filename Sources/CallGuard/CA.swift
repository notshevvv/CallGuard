import AppKit
import CoreAudio
import Foundation

/// Thin helpers over the Core Audio HAL C API.
enum CA {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func addr(_ sel: AudioObjectPropertySelector,
                     _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                     _ elem: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: elem)
    }

    static func has(_ obj: AudioObjectID, _ a: AudioObjectPropertyAddress) -> Bool {
        var a = a; return AudioObjectHasProperty(obj, &a)
    }

    static func settable(_ obj: AudioObjectID, _ a: AudioObjectPropertyAddress) -> Bool {
        var a = a; var b: DarwinBoolean = false
        guard AudioObjectHasProperty(obj, &a) else { return false }
        return AudioObjectIsPropertySettable(obj, &a, &b) == noErr && b.boolValue
    }

    static func get<T>(_ obj: AudioObjectID, _ a: AudioObjectPropertyAddress, _ def: T) -> T? {
        var a = a
        guard AudioObjectHasProperty(obj, &a) else { return nil }
        var v = def; var sz = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(obj, &a, 0, nil, &sz, &v) == noErr ? v : nil
    }

    @discardableResult
    static func set<T>(_ obj: AudioObjectID, _ a: AudioObjectPropertyAddress, _ value: T) -> OSStatus {
        var a = a; var v = value
        return AudioObjectSetPropertyData(obj, &a, 0, nil, UInt32(MemoryLayout<T>.size), &v)
    }

    static func ids(_ obj: AudioObjectID, _ a: AudioObjectPropertyAddress) -> [AudioObjectID] {
        var a = a; var sz: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(obj, &a, 0, nil, &sz) == noErr, sz > 0 else { return [] }
        var out = [AudioObjectID](repeating: 0, count: Int(sz) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(obj, &a, 0, nil, &sz, &out) == noErr else { return [] }
        return out
    }

    static func string(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String? {
        var a = addr(sel); var s: Unmanaged<CFString>?; var sz = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectHasProperty(obj, &a),
              AudioObjectGetPropertyData(obj, &a, 0, nil, &sz, &s) == noErr, let v = s else { return nil }
        return v.takeRetainedValue() as String
    }

    // MARK: devices

    static var devices: [AudioObjectID] { ids(system, addr(kAudioHardwarePropertyDevices)) }

    static func name(_ d: AudioObjectID) -> String { string(d, kAudioObjectPropertyName) ?? "Unknown device" }
    static func uid(_ d: AudioObjectID) -> String? { string(d, kAudioDevicePropertyDeviceUID) }

    static func device(uid: String) -> AudioObjectID? {
        var a = addr(kAudioHardwarePropertyTranslateUIDToDevice)
        var u = uid as CFString; var d = AudioObjectID(0); var sz = UInt32(4)
        let st = withUnsafeMutablePointer(to: &u) {
            AudioObjectGetPropertyData(system, &a, UInt32(MemoryLayout<CFString>.size), $0, &sz, &d)
        }
        return st == noErr && d != 0 ? d : nil
    }

    static func hasStreams(_ d: AudioObjectID, input: Bool) -> Bool {
        !ids(d, addr(kAudioDevicePropertyStreams, input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput)).isEmpty
    }

    static func transport(_ d: AudioObjectID) -> UInt32 { get(d, addr(kAudioDevicePropertyTransportType), UInt32(0)) ?? 0 }
    static func isBluetooth(_ d: AudioObjectID) -> Bool {
        let t = transport(d); return t == kAudioDeviceTransportTypeBluetooth || t == kAudioDeviceTransportTypeBluetoothLE
    }
    static func isBuiltIn(_ d: AudioObjectID) -> Bool { transport(d) == kAudioDeviceTransportTypeBuiltIn }
    static func isAggregateOrVirtual(_ d: AudioObjectID) -> Bool {
        let t = transport(d); return t == kAudioDeviceTransportTypeAggregate || t == kAudioDeviceTransportTypeVirtual
    }

    static var defaultInput: AudioObjectID { CA.get(system, addr(kAudioHardwarePropertyDefaultInputDevice), AudioObjectID(0)) ?? 0 }
    static var defaultOutput: AudioObjectID { CA.get(system, addr(kAudioHardwarePropertyDefaultOutputDevice), AudioObjectID(0)) ?? 0 }
    static func setDefaultInput(_ d: AudioObjectID) { set(system, addr(kAudioHardwarePropertyDefaultInputDevice), d) }

    static func sampleRate(_ d: AudioObjectID) -> Double { get(d, addr(kAudioDevicePropertyNominalSampleRate), Float64(0)) ?? 0 }

    // input mute (element 0 = main; some devices only expose per-channel elements)
    static func inputMuteElements(_ d: AudioObjectID) -> [AudioObjectPropertyElement] {
        (0...8).map { AudioObjectPropertyElement($0) }.filter {
            settable(d, addr(kAudioDevicePropertyMute, kAudioObjectPropertyScopeInput, $0))
        }
    }
    static func inputMuted(_ d: AudioObjectID, _ el: AudioObjectPropertyElement) -> Bool {
        (get(d, addr(kAudioDevicePropertyMute, kAudioObjectPropertyScopeInput, el), UInt32(0)) ?? 0) != 0
    }
    @discardableResult
    static func setInputMuted(_ d: AudioObjectID, _ el: AudioObjectPropertyElement, _ on: Bool) -> OSStatus {
        set(d, addr(kAudioDevicePropertyMute, kAudioObjectPropertyScopeInput, el), UInt32(on ? 1 : 0))
    }

    static func inputStreamCount(_ d: AudioObjectID) -> Int {
        ids(d, addr(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)).count
    }

    // MARK: processes

    static func pid(of p: AudioObjectID) -> pid_t { get(p, addr(kAudioProcessPropertyPID), pid_t(0)) ?? 0 }
    static func isRunningOutput(_ p: AudioObjectID) -> Bool { (get(p, addr(kAudioProcessPropertyIsRunningOutput), UInt32(0)) ?? 0) != 0 }
    static func isRunningInput(_ p: AudioObjectID) -> Bool { (get(p, addr(kAudioProcessPropertyIsRunningInput), UInt32(0)) ?? 0) != 0 }
    static func outputDevices(of p: AudioObjectID) -> [AudioObjectID] {
        ids(p, addr(kAudioProcessPropertyDevices, kAudioObjectPropertyScopeOutput))
    }
    static var processObjects: [AudioObjectID] { ids(system, addr(kAudioHardwarePropertyProcessObjectList)) }

    /// A short, friendly app name for a process.
    static func appName(of p: AudioObjectID) -> String {
        let bid = string(p, kAudioProcessPropertyBundleID) ?? ""
        switch bid {
        case "net.whatsapp.WhatsApp": return "WhatsApp"
        case "com.apple.FaceTime", "com.apple.avconferenced": return "FaceTime"
        case "us.zoom.xos": return "Zoom"
        case "com.microsoft.teams2", "com.microsoft.teams": return "Teams"
        case "com.hnc.Discord": return "Discord"
        case "com.tinyspeck.slackmacgap": return "Slack"
        case "ru.keepcoder.Telegram", "org.telegram.desktop": return "Telegram"
        case "com.skype.skype": return "Skype"
        case "org.whispersystems.signal-desktop": return "Signal"
        default: break
        }
        let pid = pid(of: p)
        if let app = NSRunningApplication(processIdentifier: pid), var n = app.localizedName {
            if let r = n.range(of: " Helper") { n = String(n[..<r.lowerBound]) }
            return n
        }
        if !bid.isEmpty, let last = bid.split(separator: ".").last { return String(last) }
        return "pid \(pid)"
    }

    static func processObject(pid: pid_t) -> AudioObjectID? {
        var a = addr(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var p = pid; var obj = AudioObjectID(0); var sz = UInt32(4)
        let st = AudioObjectGetPropertyData(system, &a, UInt32(MemoryLayout<pid_t>.size), &p, &sz, &obj)
        return st == noErr && obj != 0 ? obj : nil
    }

    /// Bundle IDs of processes currently recording from any input.
    static var processesUsingInput: [String] {
        ids(system, addr(kAudioHardwarePropertyProcessObjectList)).compactMap { p in
            guard (get(p, addr(kAudioProcessPropertyIsRunningInput), UInt32(0)) ?? 0) != 0 else { return nil }
            return string(p, kAudioProcessPropertyBundleID) ?? "pid \(get(p, addr(kAudioProcessPropertyPID), pid_t(0)) ?? 0)"
        }
    }
}

/// Owns a set of HAL property listeners and removes them together.
final class Listeners {
    private var items: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    func add(_ obj: AudioObjectID, _ a: AudioObjectPropertyAddress, _ handler: @escaping () -> Void) {
        var a = a
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        if AudioObjectAddPropertyListenerBlock(obj, &a, DispatchQueue.main, block) == noErr {
            items.append((obj, a, block))
        }
    }

    func removeAll() {
        for (obj, a, block) in items {
            var a = a
            AudioObjectRemovePropertyListenerBlock(obj, &a, DispatchQueue.main, block)
        }
        items.removeAll()
    }

    deinit { removeAll() }
}
