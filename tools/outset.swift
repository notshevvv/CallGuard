// outset <deviceID> mute <0|1> | get
import CoreAudio
let d = AudioObjectID(UInt32(CommandLine.arguments[1])!)
var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioObjectPropertyScopeOutput, mElement: 0)
var v: UInt32 = 0; var sz = UInt32(4)
if CommandLine.arguments[2] == "get" { AudioObjectGetPropertyData(d, &a, 0, nil, &sz, &v); print("mute=\(v)") }
else { v = UInt32(CommandLine.arguments[3])!; print("status", AudioObjectSetPropertyData(d, &a, 0, nil, 4, &v)) }
