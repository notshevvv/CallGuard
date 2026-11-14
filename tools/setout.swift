// setout <deviceID> : make this the default output device
import CoreAudio
var d = AudioObjectID(UInt32(CommandLine.arguments[1])!)
var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
print("status", AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, 4, &d))
