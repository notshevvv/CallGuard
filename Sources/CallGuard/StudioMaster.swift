import Foundation

/// A second-order IIR filter (RBJ cookbook). A struct, so it lives inline: no ARC on the audio thread.
struct Biquad {
    var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
    var z1: Float = 0, z2: Float = 0

    @inline(__always) mutating func process(_ x: Float) -> Float {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }
    mutating func reset() { z1 = 0; z2 = 0 }
    mutating func set(_ c: (Float, Float, Float, Float, Float, Float)) {
        let a0 = c.3
        b0 = c.0 / a0; b1 = c.1 / a0; b2 = c.2 / a0; a1 = c.4 / a0; a2 = c.5 / a0
    }

    static func lowpass(_ f: Float, _ q: Float, _ fs: Float) -> (Float, Float, Float, Float, Float, Float) {
        let w = 2 * Float.pi * min(f, fs * 0.45) / fs, c = cosf(w), al = sinf(w) / (2 * q)
        return ((1 - c) / 2, 1 - c, (1 - c) / 2, 1 + al, -2 * c, 1 - al)
    }
    static func highpass(_ f: Float, _ q: Float, _ fs: Float) -> (Float, Float, Float, Float, Float, Float) {
        let w = 2 * Float.pi * min(f, fs * 0.45) / fs, c = cosf(w), al = sinf(w) / (2 * q)
        return ((1 + c) / 2, -(1 + c), (1 + c) / 2, 1 + al, -2 * c, 1 - al)
    }
    static func peak(_ f: Float, _ q: Float, _ db: Float, _ fs: Float) -> (Float, Float, Float, Float, Float, Float) {
        let A = powf(10, db / 40), w = 2 * Float.pi * min(f, fs * 0.45) / fs, c = cosf(w), al = sinf(w) / (2 * q)
        return (1 + al * A, -2 * c, 1 - al * A, 1 + al / A, -2 * c, 1 - al / A)
    }
    static func highShelf(_ f: Float, _ db: Float, _ fs: Float) -> (Float, Float, Float, Float, Float, Float) {
        let A = powf(10, db / 40), w = 2 * Float.pi * min(f, fs * 0.45) / fs, c = cosf(w), s = sinf(w)
        let al = s / 2 * sqrtf(2), sA = 2 * sqrtf(A) * al
        return (A * ((A + 1) + (A - 1) * c + sA), -2 * A * ((A - 1) + (A + 1) * c), A * ((A + 1) + (A - 1) * c - sA),
                (A + 1) - (A - 1) * c + sA, 2 * ((A - 1) - (A + 1) * c), (A + 1) - (A - 1) * c - sA)
    }
    static func lowShelf(_ f: Float, _ db: Float, _ fs: Float) -> (Float, Float, Float, Float, Float, Float) {
        let A = powf(10, db / 40), w = 2 * Float.pi * min(f, fs * 0.45) / fs, c = cosf(w), s = sinf(w)
        let al = s / 2 * sqrtf(2), sA = 2 * sqrtf(A) * al
        return (A * ((A + 1) - (A - 1) * c + sA), 2 * A * ((A - 1) - (A + 1) * c), A * ((A + 1) - (A - 1) * c - sA),
                (A + 1) + (A - 1) * c + sA, -2 * ((A - 1) + (A + 1) * c), (A + 1) + (A - 1) * c - sA)
    }
}

/// "Studio Master": a mastering-style chain that makes earbuds and laptop speakers sound
/// bigger and more expensive. Media only. In order:
///  1. clean the floor: cut sub-sonic rumble (<22 Hz) that wastes headroom
///  2. de-mud: a gentle dip at 320 Hz where mixes get boxy
///  3. tight mono bass: everything under 120 Hz summed to mono (punchier, centred)
///  4. harmonic bass: adds the overtones of the bass notes, so small drivers that can't
///     move enough air still let you *hear* deep bass (the "missing fundamental" effect)
///  5. sub warmth: a small low shelf at 70 Hz
///  6. presence and air: +1 dB at 3 kHz, high shelf at 11 kHz for sparkle
///  7. exciter: soft saturation of the top end for detail
///  8. wider highs while the bass stays centred
/// `amount` (0…1) scales every stage together.
final class StudioMaster: @unchecked Sendable {
    private var subL = Biquad(), subR = Biquad()
    private var mudL = Biquad(), mudR = Biquad()
    private var xoL = Biquad(), xoR = Biquad()            // crossover low-pass, 120 Hz
    private var vbHP = Biquad(), vbLP = Biquad()          // harmonic band 90–450 Hz
    private var vbDC = Biquad()                           // removes the rectifier's DC
    private var warm = Biquad()
    private var presL = Biquad(), presR = Biquad()
    private var airL = Biquad(), airR = Biquad()
    private var exL = Biquad(), exR = Biquad()            // exciter band, above 5 kHz
    private var amount: Float = 0
    private var rate: Float = 0
    private(set) var on = false

    func configure(sampleRate fs: Float, amount a: Float) {
        let a = min(max(a, 0), 1)
        on = a > 0.005
        let changed = fs != rate || abs(a - amount) > 0.0001
        amount = a
        guard changed else { return }
        if fs != rate {
            rate = fs
            subL.reset(); subR.reset(); mudL.reset(); mudR.reset(); xoL.reset(); xoR.reset()
            vbHP.reset(); vbLP.reset(); vbDC.reset(); warm.reset(); presL.reset(); presR.reset()
            airL.reset(); airR.reset(); exL.reset(); exR.reset()
        }
        let sub = Biquad.highpass(22, 0.707, fs); subL.set(sub); subR.set(sub)
        let mud = Biquad.peak(320, 0.9, -2.5 * a, fs); mudL.set(mud); mudR.set(mud)
        let xo = Biquad.lowpass(120, 0.707, fs); xoL.set(xo); xoR.set(xo)
        vbHP.set(Biquad.highpass(90, 0.707, fs)); vbLP.set(Biquad.lowpass(450, 0.707, fs))
        vbDC.set(Biquad.highpass(20, 0.707, fs))
        warm.set(Biquad.lowShelf(70, 2 * a, fs))
        let pres = Biquad.peak(3000, 1.0, 1 * a, fs); presL.set(pres); presR.set(pres)
        let air = Biquad.highShelf(11000, 3.5 * a, fs); airL.set(air); airR.set(air)
        let ex = Biquad.highpass(5000, 0.707, fs); exL.set(ex); exR.set(ex)
    }

    @inline(__always) func process(_ l: inout Float, _ r: inout Float) {
        let a = amount
        var xl = subL.process(l), xr = subR.process(r)
        xl = mudL.process(xl); xr = mudR.process(xr)
        // Split at 120 Hz (complementary, so the bands add back to the original).
        let lowL = xoL.process(xl), lowR = xoR.process(xr)
        var hiL = xl - lowL, hiR = xr - lowR
        var low = (lowL + lowR) * 0.5
        // Harmonic bass: full-wave rectifying the bass gives its 2nd harmonic in proportion
        // to the note's level; keep only the 90–450 Hz overtone band and blend it in.
        let harm = vbLP.process(vbHP.process(vbDC.process(abs(low))))
        low += harm * 0.9 * a
        low = warm.process(low)
        // Presence, air, exciter, then a slightly wider top end.
        hiL = airL.process(presL.process(hiL)); hiR = airR.process(presR.process(hiR))
        let eL = exL.process(hiL), eR = exR.process(hiR)
        // Only the saturation's harmonics are added (tanh minus the straight line), so the
        // exciter brings detail without a second treble boost.
        hiL += (tanhf(eL * 4) * 0.25 - eL) * 1.5 * a
        hiR += (tanhf(eR * 4) * 0.25 - eR) * 1.5 * a
        let m = (hiL + hiR) * 0.5, s = (hiL - hiR) * 0.5 * (1 + 0.25 * a)
        l = low + m + s
        r = low + m - s
    }
}
