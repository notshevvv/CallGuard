import Foundation

/// Real-time effects for the media bus (never the call voice): pitch shift ("Slowed" /
/// "Sped up"), a harmony layer, reverb ("Ambience") and stereo width.
/// Everything is allocated up front; `process` never allocates or locks.
final class Effects: @unchecked Sendable {

    // MARK: pitch shifter (two crossfaded delay-line taps)

    /// Shifts pitch without changing timing, so live audio stays in sync with video.
    final class PitchShifter: @unchecked Sendable {
        private let size = 16384, mask = 16383
        private let buf: UnsafeMutablePointer<Float>
        private var w = 0
        private var d: Float = 0
        var window: Float = 2400        // samples (~50 ms)
        var ratio: Float = 1

        init() { buf = .allocate(capacity: size); buf.initialize(repeating: 0, count: size) }
        deinit { buf.deallocate() }

        func reset() { memset(buf, 0, size * 4); d = 0 }

        @inline(__always) private func read(_ delay: Float) -> Float {
            let pos = Float(w) - delay
            let i = Int(pos.rounded(.down))
            let f = pos - Float(i)
            let a = buf[i & mask], b = buf[(i + 1) & mask]
            return a + (b - a) * f
        }

        @inline(__always) func process(_ x: Float) -> Float {
            buf[w & mask] = x
            let W = window
            d += 1 - ratio
            if d >= W { d -= W } else if d < 0 { d += W }
            var d2 = d + W * 0.5
            if d2 >= W { d2 -= W }
            // sin² / cos² windows sum to exactly 1, so the level stays steady.
            let s = sinf(.pi * d / W)
            let g1 = s * s, g2 = 1 - g1
            let y = read(d) * g1 + read(d2) * g2
            w = (w + 1) & mask
            return y
        }
    }

    // MARK: Freeverb (Jezar's public-domain design)

    final class Comb: @unchecked Sendable {
        private let buf: UnsafeMutablePointer<Float>
        private let capacity: Int
        private var length: Int
        private var idx = 0
        private var store: Float = 0
        var feedback: Float = 0.84
        var damp: Float = 0.2

        init(capacity: Int) { self.capacity = capacity; length = capacity
            buf = .allocate(capacity: capacity); buf.initialize(repeating: 0, count: capacity) }
        deinit { buf.deallocate() }
        func setLength(_ n: Int) { length = max(1, min(n, capacity)); idx = 0; store = 0; memset(buf, 0, capacity * 4) }

        @inline(__always) func process(_ x: Float) -> Float {
            let out = buf[idx]
            store = out * (1 - damp) + store * damp
            buf[idx] = x + store * feedback
            idx += 1; if idx >= length { idx = 0 }
            return out
        }
    }

    final class Allpass: @unchecked Sendable {
        private let buf: UnsafeMutablePointer<Float>
        private let capacity: Int
        private var length: Int
        private var idx = 0

        init(capacity: Int) { self.capacity = capacity; length = capacity
            buf = .allocate(capacity: capacity); buf.initialize(repeating: 0, count: capacity) }
        deinit { buf.deallocate() }
        func setLength(_ n: Int) { length = max(1, min(n, capacity)); idx = 0; memset(buf, 0, capacity * 4) }

        @inline(__always) func process(_ x: Float) -> Float {
            let b = buf[idx]
            buf[idx] = x + b * 0.5
            idx += 1; if idx >= length { idx = 0 }
            return b - x
        }
    }

    private static let combTuning = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
    private static let allpassTuning = [556, 441, 341, 225]
    private static let spread = 23
    private static let maxScale = 192_000.0 / 44_100.0

    private let combsL: [Comb], combsR: [Comb], apL: [Allpass], apR: [Allpass]
    private let pitchL = PitchShifter(), pitchR = PitchShifter()
    private let harmL = PitchShifter(), harmR = PitchShifter()

    // Settings (written by DSP.update on the audio thread).
    private(set) var pitchOn = false, harmonyOn = false, reverbOn = false, widthOn = false
    private var harmony: Float = 0, width: Float = 1
    private var wetTarget: Float = 0, wet: Float = 0, wetSmooth: Float = 0.999
    private var configuredRate: Float = 0

    var active: Bool { pitchOn || harmonyOn || reverbOn || widthOn }

    init() {
        let cap = { (n: Int) in Int(Double(n + Self.spread) * Self.maxScale) + 2 }
        combsL = Self.combTuning.map { Comb(capacity: cap($0)) }
        combsR = Self.combTuning.map { Comb(capacity: cap($0)) }
        apL = Self.allpassTuning.map { Allpass(capacity: cap($0)) }
        apR = Self.allpassTuning.map { Allpass(capacity: cap($0)) }
    }

    /// semitones: −12…+12. harmonyMix, reverbMix, room, warmth: 0…1. widthAmount: 0…2.
    func configure(sampleRate fs: Float, semitones: Float, harmonyMix: Float, reverbMix: Float,
                   room: Float, warmth: Float, widthAmount: Float) {
        if fs != configuredRate {
            configuredRate = fs
            let scale = Double(fs) / 44_100
            for (i, n) in Self.combTuning.enumerated() {
                combsL[i].setLength(Int(Double(n) * scale))
                combsR[i].setLength(Int(Double(n + Self.spread) * scale))
            }
            for (i, n) in Self.allpassTuning.enumerated() {
                apL[i].setLength(Int(Double(n) * scale))
                apR[i].setLength(Int(Double(n + Self.spread) * scale))
            }
            for p in [pitchL, pitchR, harmL, harmR] { p.reset(); p.window = 0.05 * fs }
            wetSmooth = expf(-1 / (0.05 * fs))
        }
        let ratio = powf(2, semitones / 12)
        pitchOn = abs(semitones) > 0.05
        pitchL.ratio = ratio; pitchR.ratio = ratio
        harmony = harmonyMix * 0.6
        harmonyOn = harmonyMix > 0.005
        harmL.ratio = 2; harmR.ratio = 2          // an octave above
        wetTarget = reverbMix
        reverbOn = reverbMix > 0.005 || wet > 0.001
        let fb = 0.70 + 0.28 * min(max(room, 0), 1)
        let dmp = 0.15 + 0.6 * min(max(warmth, 0), 1)
        for c in combsL { c.feedback = fb; c.damp = dmp }
        for c in combsR { c.feedback = fb; c.damp = dmp }
        width = widthAmount
        widthOn = abs(widthAmount - 1) > 0.01
    }

    @inline(__always) func process(_ l: inout Float, _ r: inout Float) {
        if pitchOn { l = pitchL.process(l); r = pitchR.process(r) }
        if harmonyOn {
            let hl = harmL.process(l), hr = harmR.process(r)
            l += hl * harmony; r += hr * harmony
        }
        if reverbOn {
            wet = wetTarget + (wet - wetTarget) * wetSmooth
            let input = (l + r) * 0.015
            var ol: Float = 0, or: Float = 0
            for c in combsL { ol += c.process(input) }
            for c in combsR { or += c.process(input) }
            for a in apL { ol = a.process(ol) }
            for a in apR { or = a.process(or) }
            let dry = 1 - 0.35 * wet
            l = l * dry + ol * wet * 3
            r = r * dry + or * wet * 3
        }
        if widthOn {
            let m = (l + r) * 0.5, s = (l - r) * 0.5 * width
            l = m + s; r = m - s
        }
    }
}
