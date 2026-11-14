// vpio <inUID> <outUID> <seconds> [duckLevel 10|20|30|40 = min..max] : runs a voice-processing IO unit like a call app
import AudioToolbox
import CoreAudio
import Foundation
func dev(_ uid: String) -> AudioObjectID {
  var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
  var d = AudioObjectID(0); var sz = UInt32(4); var u = uid as CFString
  AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, UInt32(MemoryLayout<CFString>.size), &u, &sz, &d); return d }
let A = CommandLine.arguments
var desc = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_VoiceProcessingIO, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
let comp = AudioComponentFindNext(nil, &desc)!
var unit: AudioUnit?; AudioComponentInstanceNew(comp, &unit); let u = unit!
var one: UInt32 = (ProcessInfo.processInfo.environment["NOIN"] != nil) ? 0 : 1
AudioUnitSetProperty(u, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &one, 4)
var din = dev(A[1]), dout = dev(A[2])
print("set in", AudioUnitSetProperty(u, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 1, &din, 4))
print("set out", AudioUnitSetProperty(u, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &dout, 4))
if A.count > 4 {
  var cfg = AUVoiceIOOtherAudioDuckingConfiguration(mEnableAdvancedDucking: false, mDuckingLevel: AUVoiceIOOtherAudioDuckingLevel(rawValue: UInt32(A[4])!)!)
  print("duck cfg", AudioUnitSetProperty(u, kAUVoiceIOProperty_OtherAudioDuckingConfiguration, kAudioUnitScope_Global, 0, &cfg, UInt32(MemoryLayout.size(ofValue: cfg))))
}
var cb = AURenderCallbackStruct(inputProc: { _, _, _, _, _, io in
  if let io { for b in UnsafeMutableAudioBufferListPointer(io) { memset(b.mData, 0, Int(b.mDataByteSize)) } }; return noErr }, inputProcRefCon: nil)
AudioUnitSetProperty(u, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &cb, UInt32(MemoryLayout<AURenderCallbackStruct>.size))
print("init", AudioUnitInitialize(u), "start", AudioOutputUnitStart(u)); fflush(stdout)
Thread.sleep(forTimeInterval: Double(A[3])!)
AudioOutputUnitStop(u); AudioUnitUninitialize(u); print("vpio stopped")
