// inset <deviceID> mute <0|1> | vol <0..1>
import CoreAudio
let d = AudioObjectID(UInt32(CommandLine.arguments[1])!)
let what = CommandLine.arguments[2]
var a = AudioObjectPropertyAddress(mSelector: what == "mute" ? kAudioDevicePropertyMute : kAudioDevicePropertyVolumeScalar, mScope: kAudioObjectPropertyScopeInput, mElement: 0)
var st: OSStatus
if what == "mute" { var v = UInt32(CommandLine.arguments[3])!; st = AudioObjectSetPropertyData(d, &a, 0, nil, 4, &v) }
else { var v = Float32(CommandLine.arguments[3])!; st = AudioObjectSetPropertyData(d, &a, 0, nil, 4, &v) }
print("status \(st)")
