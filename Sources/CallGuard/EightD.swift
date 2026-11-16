import Foundation

/// "8D audio": the music slowly circles your head. Earphones only (on speakers it just
/// sounds like panning). Media only: the call voice always stays in the centre.
///
/// Per sample: a slow rotation angle θ; the sound's left/right position is sin θ and its
/// front/back position cos θ. We use the three cues the brain uses to place a sound:
///  - level: equal-power panning between the ears
///  - timing: the far ear hears it up to 0.6 ms later (interaural time difference)
///  - head shadow: the far ear hears it duller (high frequencies blocked by the head)
/// plus "behind you" cues: slightly quieter and darker when cos θ < 0.
final class EightD: @unchecked Sendable {
    private let size = 256, mask = 255
    private let bufL: UnsafeMutablePointer<Float>, bufR: UnsafeMutablePointer<Float>
    private var w = 0
    private var theta: Float = 0
    private var step: Float = 0
    private var maxITD: Float = 29           // samples (0.6 ms at 48 kHz)
    private var shadeL: Float = 0, shadeR: Float = 0, rearL: Float = 0, rearR: Float = 0
    private var fs: Float = 48000
    private var mix: Float = 0, mixTarget: Float = 0, mixSmooth: Float = 0.9995

    init() {
        bufL = .allocate(capacity: size); bufL.initialize(repeating: 0, count: size)
        bufR = .allocate(capacity: size); bufR.initialize(repeating: 0, count: size)
    }
    deinit { bufL.deallocate(); bufR.deallocate() }

    /// `secondsPerTurn`: one full circle (6 = fast, 16 = slow). `on` fades in/out smoothly.
    func configure(sampleRate: Float, on: Bool, secondsPerTurn: Float) {
        fs = max(sampleRate, 8000)
        step = 2 * .pi / (max(secondsPerTurn, 2) * fs)
        maxITD = 0.0006 * fs
        mixSmooth = expf(-1 / (0.3 * fs))
        mixTarget = on ? 1 : 0
    }

    var active: Bool { mixTarget > 0 || mix > 0.0005 }

    @inline(__always) private func read(_ b: UnsafeMutablePointer<Float>, _ delay: Float) -> Float {
        let pos = Float(w) - delay
        let i = Int(pos.rounded(.down)), f = pos - Float(i)
        let a = b[i & mask], c = b[(i + 1) & mask]
        return a + (c - a) * f
    }

    /// One-pole low-pass coefficient for a cutoff in Hz.
    @inline(__always) private func coef(_ hz: Float) -> Float { expf(-2 * .pi * hz / fs) }

    @inline(__always) func process(_ l: inout Float, _ r: inout Float) {
        mix = mixTarget + (mix - mixTarget) * mixSmooth
        // Keep a little of the original stereo so it doesn't sound like mono radio.
        let mid = (l + r) * 0.5, side = (l - r) * 0.5
        bufL[w & mask] = mid
        bufR[w & mask] = mid
        theta += step
        if theta > 2 * .pi { theta -= 2 * .pi }
        let x = sinf(theta)                    // −1 left … +1 right
        let front = cosf(theta)                // +1 front … −1 behind
        // Level: equal-power pan.
        let a = (x + 1) * .pi / 4
        let gL = cosf(a), gR = sinf(a)
        // Timing: delay the far ear.
        let dL = x > 0 ? x * maxITD : 0
        let dR = x < 0 ? -x * maxITD : 0
        var sL = read(bufL, dL) * gL
        var sR = read(bufR, dR) * gR
        // Head shadow: far ear gets duller (down to ~3 kHz when fully to one side).
        let cL = coef(20000 - 17000 * max(x, 0)), cR = coef(20000 - 17000 * max(-x, 0))
        shadeL = sL + (shadeL - sL) * cL; sL = shadeL
        shadeR = sR + (shadeR - sR) * cR; sR = shadeR
        // Behind: darker and a little quieter.
        let back = max(-front, 0)
        let cb = coef(16000 - 10000 * back)
        rearL = sL + (rearL - sL) * cb; rearR = sR + (rearR - sR) * cb
        let rearGain = 1 - 0.2 * back
        sL = rearL * rearGain * 1.414        // +3 dB so the centre level matches the original
        sR = rearR * rearGain * 1.414
        sL += side * 0.35; sR -= side * 0.35
        w = (w + 1) & mask
        l = l + (sL - l) * mix
        r = r + (sR - r) * mix
    }
}
