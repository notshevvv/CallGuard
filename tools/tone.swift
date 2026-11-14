// tone <deviceUID> <freqHz> <dBFS> <seconds> : plays a sine directly on one output device
import CoreAudio
import Foundation
let uid = CommandLine.arguments[1] as CFString
let f = Double(CommandLine.arguments[2])!, amp = Float(pow(10, Double(CommandLine.arguments[3])!/20)), secs = Double(CommandLine.arguments[4])!
var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
var dev = AudioObjectID(0); var sz = UInt32(4); var u: CFString = uid
AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, UInt32(MemoryLayout<CFString>.size), &u, &sz, &dev)
var ra = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
var sr: Float64 = 48000; sz = 8; AudioObjectGetPropertyData(dev, &ra, 0, nil, &sz, &sr)
final class S { var ph = 0.0 }; let s = S(); let inc = 2 * Double.pi * f / sr
var pid: AudioDeviceIOProcID?
AudioDeviceCreateIOProcIDWithBlock(&pid, dev, nil) { _, _, _, out, _ in
    for b in UnsafeMutableAudioBufferListPointer(out) {
        let ch = Int(b.mNumberChannels); let p = b.mData!.assumingMemoryBound(to: Float.self)
        let n = Int(b.mDataByteSize) / 4 / ch
        var ph = s.ph
        for i in 0..<n { let v = amp * Float(sin(ph)); ph += inc; for c in 0..<ch { p[i*ch+c] = v } }
        s.ph = ph.truncatingRemainder(dividingBy: 2 * Double.pi)
    }
}
AudioDeviceStart(dev, pid); print("pid \(getpid()) playing"); fflush(stdout)
Thread.sleep(forTimeInterval: secs); AudioDeviceStop(dev, pid)
