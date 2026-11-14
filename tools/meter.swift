// meter <deviceUID> <seconds> : records from an input device via HAL IOProc, prints peak/RMS dBFS
import CoreAudio
import Foundation
let uid = CommandLine.arguments[1] as CFString
let secs = Double(CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "1")!
var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
var dev = AudioObjectID(0); var sz = UInt32(4); var u: CFString = uid
AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, UInt32(MemoryLayout<CFString>.size), &u, &sz, &dev)
guard dev != 0 else { print("no device"); exit(1) }
var srsz = UInt32(8); AudioObjectGetPropertyData(dev, &sra, 0, nil, &srsz, &devSR)
final class Acc { var peak: Float = 0; var sum: Double = 0; var n = 0; var nonzero = 0; var gs1 = 0.0; var gs2 = 0.0; var gn = 0 }
let gf = Double(CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "0")!
var sra = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
var devSR: Float64 = 48000
let acc = Acc()
var procID: AudioDeviceIOProcID?
let st = AudioDeviceCreateIOProcIDWithBlock(&procID, dev, nil) { _, inData, _, _, _ in
    let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
    for b in abl {
        guard let p = b.mData?.assumingMemoryBound(to: Float.self) else { continue }
        let c = Int(b.mDataByteSize) / 4
        let ch = Int(b.mNumberChannels); let coef = 2*cos(2*Double.pi*gf/devSR)
        if gf > 0 { var i = 0; while i < c { let s0 = Double(p[i]) + coef*acc.gs1 - acc.gs2; acc.gs2 = acc.gs1; acc.gs1 = s0; acc.gn += 1; i += ch } }
        for i in 0..<c { let v = abs(p[i]); if v > acc.peak { acc.peak = v }; acc.sum += Double(v*v); if v != 0 { acc.nonzero += 1 } }
        acc.n += c
    }
}
guard st == noErr else { print("ioproc err \(st)"); exit(1) }
AudioDeviceStart(dev, procID)
Thread.sleep(forTimeInterval: 0.3) // settle
acc.peak = 0; acc.sum = 0; acc.n = 0; acc.nonzero = 0; acc.gs1 = 0; acc.gs2 = 0; acc.gn = 0
Thread.sleep(forTimeInterval: secs)
AudioDeviceStop(dev, procID); AudioDeviceDestroyIOProcID(dev, procID!)
let rms = acc.n > 0 ? sqrt(acc.sum / Double(acc.n)) : 0
func db(_ x: Double) -> String { x <= 0 ? "-inf" : String(format: "%.1f", 20*log10(x)) }
let coefF = 2*cos(2*Double.pi*gf/devSR); let pw = acc.gs1*acc.gs1 + acc.gs2*acc.gs2 - coefF*acc.gs1*acc.gs2
let toneAmp = acc.gn > 0 ? 2*sqrt(max(pw,0))/Double(acc.gn) : 0
print(gf > 0 ? "tone(\(Int(gf))Hz ch0)=\(db(toneAmp)) dB  " : "", terminator: "")
print("samples=\(acc.n) nonzero=\(acc.nonzero) peak=\(db(Double(acc.peak))) dBFS rms=\(db(rms)) dBFS")
