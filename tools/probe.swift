import CoreAudio
import Foundation

func get<T>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ elem: AudioObjectPropertyElement = kAudioObjectPropertyElementMain, def: T) -> T? {
    var a = AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: elem)
    guard AudioObjectHasProperty(obj, &a) else { return nil }
    var v = def; var sz = UInt32(MemoryLayout<T>.size)
    let st = AudioObjectGetPropertyData(obj, &a, 0, nil, &sz, &v)
    return st == noErr ? v : nil
}
func list(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector) -> [AudioObjectID] {
    var a = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var sz: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(obj, &a, 0, nil, &sz) == noErr else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(sz)/4)
    AudioObjectGetPropertyData(obj, &a, 0, nil, &sz, &ids)
    return ids
}
func str(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String {
    var a = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var s: Unmanaged<CFString>? = nil; var sz = UInt32(MemoryLayout<CFString?>.size)
    guard AudioObjectGetPropertyData(obj, &a, 0, nil, &sz, &s) == noErr, let v = s else { return "?" }
    return v.takeRetainedValue() as String
}
func settable(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope, _ el: UInt32) -> String {
    var a = AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: el)
    guard AudioObjectHasProperty(obj, &a) else { return "-" }
    var b: DarwinBoolean = false; AudioObjectIsPropertySettable(obj, &a, &b); return b.boolValue ? "rw" : "ro"
}
let sys = AudioObjectID(kAudioObjectSystemObject)
let defIn: AudioObjectID = get(sys, kAudioHardwarePropertyDefaultInputDevice, def: 0) ?? 0
let defOut: AudioObjectID = get(sys, kAudioHardwarePropertyDefaultOutputDevice, def: 0) ?? 0
print("default in \(defIn) out \(defOut)")
for d in list(sys, kAudioHardwarePropertyDevices) {
    let name = str(d, kAudioObjectPropertyName)
    let uid = str(d, kAudioDevicePropertyDeviceUID)
    let inS = list(d, kAudioDevicePropertyStreams).count
    var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeInput, mElement: 0)
    var sz: UInt32 = 0; AudioObjectGetPropertyDataSize(d, &a, 0, nil, &sz)
    let running: UInt32 = get(d, kAudioDevicePropertyDeviceIsRunningSomewhere, def: 0) ?? 9
    let sr: Float64 = get(d, kAudioDevicePropertyNominalSampleRate, def: 0) ?? 0
    var info = "[\(d)] \(name) uid=\(uid) instreams=\(sz/4) streams=\(inS) sr=\(sr) runningSomewhere=\(running)"
    for el: UInt32 in [0,1,2] {
        let m = settable(d, kAudioDevicePropertyMute, kAudioObjectPropertyScopeInput, el)
        let v = settable(d, kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeInput, el)
        if m != "-" || v != "-" {
            let mv: UInt32 = get(d, kAudioDevicePropertyMute, kAudioObjectPropertyScopeInput, el, def: 0) ?? 99
            let vv: Float32 = get(d, kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeInput, el, def: 0) ?? -1
            info += " | in el\(el) mute=\(m):\(mv) vol=\(v):\(vv)"
        }
    }
    print(info)
}
print("--- processes using audio")
for p in list(sys, kAudioHardwarePropertyProcessObjectList) {
    let pid: pid_t = get(p, kAudioProcessPropertyPID, def: 0) ?? 0
    let bid = str(p, kAudioProcessPropertyBundleID)
    let ri: UInt32 = get(p, kAudioProcessPropertyIsRunningInput, def: 0) ?? 0
    let ro: UInt32 = get(p, kAudioProcessPropertyIsRunningOutput, def: 0) ?? 0
    if ri != 0 || ro != 0 { print("pid \(pid) \(bid) in=\(ri) out=\(ro)") }
}
