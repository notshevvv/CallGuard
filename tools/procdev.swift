import CoreAudio
func ids(_ o: AudioObjectID, _ s: AudioObjectPropertySelector, _ sc: AudioObjectPropertyScope) -> [AudioObjectID] {
  var a = AudioObjectPropertyAddress(mSelector: s, mScope: sc, mElement: 0); var sz: UInt32 = 0
  guard AudioObjectGetPropertyDataSize(o, &a, 0, nil, &sz) == noErr, sz > 0 else { return [] }
  var r = [AudioObjectID](repeating: 0, count: Int(sz)/4); AudioObjectGetPropertyData(o, &a, 0, nil, &sz, &r); return r }
for p in ids(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList, kAudioObjectPropertyScopeGlobal) {
  var a = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID, mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
  var pid: pid_t = 0; var sz = UInt32(4); AudioObjectGetPropertyData(p, &a, 0, nil, &sz, &pid)
  let o = ids(p, kAudioProcessPropertyDevices, kAudioObjectPropertyScopeOutput), i = ids(p, kAudioProcessPropertyDevices, kAudioObjectPropertyScopeInput)
  if !o.isEmpty || !i.isEmpty { print("pid \(pid) out=\(o) in=\(i)") }
}
