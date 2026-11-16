import AppKit
import CoreAudio
import Foundation

/// Development checks (run the binary from Terminal):
///   --selftest-dsp                         offline DSP checks (no audio devices touched)
///   --selftest-engine <mediaPid> <callPid|0> <outputUID> <gain%> <bassDB> <seconds>
///                                          real taps on just those processes, played on <outputUID>
///   --selftest-mic <deviceUID> <seconds>   lock only one mic, then release
///   --shot <png> [dark|light]              README screenshot of the panel in demo mode
enum SelfTest {
    static func db(_ x: Float) -> String { x <= 0 ? "-inf" : String(format: "%.1f", 20 * log10f(x)) }

    static func run(_ a: [String]) -> Never {
        switch a[1] {
        case "--selftest-dsp": dspTests()
        case "--selftest-engine" where a.count >= 8: engineTest(a)
        case "--selftest-mic" where a.count >= 4: micTest(a)
        case "--shot" where a.count >= 3: MainActor.assumeIsolated { shot(a) }
        default: print("unknown selftest"); exit(1)
        }
    }

    // MARK: offline DSP

    /// Feeds synthetic sine waves through the DSP and measures the output (after it settles).
    static func measure(_ dsp: DSP, media: (Double, Float), call: (Double, Float)? = nil, seconds: Double = 2) -> (Float, Float) {
        let fs = 48000.0, n = 512
        let inList = AudioBufferList.allocate(maximumBuffers: call == nil ? 1 : 2)
        let outList = AudioBufferList.allocate(maximumBuffers: 1)
        let mBuf = UnsafeMutablePointer<Float>.allocate(capacity: n * 2)
        let cBuf = UnsafeMutablePointer<Float>.allocate(capacity: n * 2)
        let oBuf = UnsafeMutablePointer<Float>.allocate(capacity: n * 2)
        inList[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(n * 8), mData: mBuf)
        if call != nil { inList[1] = AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(n * 8), mData: cBuf) }
        outList[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(n * 8), mData: oBuf)
        dsp.sampleRate = Float(fs); dsp.hasCallBus = call != nil; dsp.tapOffset = 0; dsp.coeffVersion &+= 1
        var ph = 0.0, phc = 0.0, peak: Float = 0, blocks = Int(seconds * fs) / n
        for b in 0..<blocks {
            for i in 0..<n {
                let v = media.1 * Float(sin(ph)); mBuf[2 * i] = v; mBuf[2 * i + 1] = v; ph += 2 * .pi * media.0 / fs
                if let call { let c = call.1 * Float(sin(phc)); cBuf[2 * i] = c; cBuf[2 * i + 1] = c; phc += 2 * .pi * call.0 / fs }
            }
            dsp.process(input: inList, output: outList)
            if b > blocks * 3 / 4 { for i in 0..<(2 * n) { peak = max(peak, abs(oBuf[i])) } }
        }
        let lim = dsp.limiting
        mBuf.deallocate(); cBuf.deallocate(); oBuf.deallocate(); free(inList.unsafeMutablePointer); free(outList.unsafeMutablePointer)
        return (peak, lim)
    }


    /// Renders a sine (or a single click when freq == 0) through the DSP; returns the left output.
    static func render(_ dsp: DSP, freq: Double, amp: Float, seconds: Double, call: (Double, Float)? = nil) -> [Float] {
        let fs = 48000.0, n = 512
        let inList = AudioBufferList.allocate(maximumBuffers: call == nil ? 1 : 2)
        let outList = AudioBufferList.allocate(maximumBuffers: 1)
        let mBuf = UnsafeMutablePointer<Float>.allocate(capacity: n * 2)
        let cBuf = UnsafeMutablePointer<Float>.allocate(capacity: n * 2)
        let oBuf = UnsafeMutablePointer<Float>.allocate(capacity: n * 2)
        inList[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(n * 8), mData: mBuf)
        if call != nil { inList[1] = AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(n * 8), mData: cBuf) }
        outList[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(n * 8), mData: oBuf)
        dsp.sampleRate = Float(fs); dsp.hasCallBus = call != nil; dsp.tapOffset = 0; dsp.coeffVersion &+= 1
        var out: [Float] = []; var ph = 0.0, phc = 0.0, t = 0
        for _ in 0..<(Int(seconds * fs) / n) {
            for i in 0..<n {
                let v: Float = freq == 0 ? (t == 0 ? amp : 0) : amp * Float(sin(ph))
                mBuf[2 * i] = v; mBuf[2 * i + 1] = v; ph += 2 * .pi * freq / fs; t += 1
                if let call { let c = call.1 * Float(sin(phc)); cBuf[2 * i] = c; cBuf[2 * i + 1] = c; phc += 2 * .pi * call.0 / fs }
            }
            dsp.process(input: inList, output: outList)
            for i in 0..<n { out.append(oBuf[2 * i]) }
        }
        mBuf.deallocate(); cBuf.deallocate(); oBuf.deallocate(); free(inList.unsafeMutablePointer); free(outList.unsafeMutablePointer)
        return out
    }

    /// Level (dB) of one frequency in a stretch of samples.
    static func tone(_ x: ArraySlice<Float>, _ f: Double) -> Float {
        let k = 2 * cos(2 * .pi * f / 48000); var s1 = 0.0, s2 = 0.0
        for v in x { let s0 = Double(v) + k * s1 - s2; s2 = s1; s1 = s0 }
        let p = s1 * s1 + s2 * s2 - k * s1 * s2
        return Float(20 * log10(max(2 * sqrt(max(p, 0)) / Double(x.count), 1e-9)))
    }


    /// Like render, but returns both channels.
    static func renderLR(_ dsp: DSP, freq: Double, amp: Float, seconds: Double, call: (Double, Float)? = nil) -> ([Float], [Float]) {
        let fs = 48000.0, n = 480
        let inList = AudioBufferList.allocate(maximumBuffers: call == nil ? 1 : 2)
        let outList = AudioBufferList.allocate(maximumBuffers: 1)
        let mBuf = UnsafeMutablePointer<Float>.allocate(capacity: n * 2)
        let cBuf = UnsafeMutablePointer<Float>.allocate(capacity: n * 2)
        let oBuf = UnsafeMutablePointer<Float>.allocate(capacity: n * 2)
        inList[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(n * 8), mData: mBuf)
        if call != nil { inList[1] = AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(n * 8), mData: cBuf) }
        outList[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(n * 8), mData: oBuf)
        dsp.sampleRate = Float(fs); dsp.hasCallBus = call != nil; dsp.tapOffset = 0; dsp.coeffVersion &+= 1
        var L: [Float] = [], R: [Float] = []; var ph = 0.0, phc = 0.0
        for _ in 0..<(Int(seconds * fs) / n) {
            for i in 0..<n {
                let v = amp * Float(sin(ph)); mBuf[2 * i] = v; mBuf[2 * i + 1] = v; ph += 2 * .pi * freq / fs
                if let call { let c = call.1 * Float(sin(phc)); cBuf[2 * i] = c; cBuf[2 * i + 1] = c; phc += 2 * .pi * call.0 / fs }
            }
            dsp.process(input: inList, output: outList)
            for i in 0..<n { L.append(oBuf[2 * i]); R.append(oBuf[2 * i + 1]) }
        }
        mBuf.deallocate(); cBuf.deallocate(); oBuf.deallocate(); free(inList.unsafeMutablePointer); free(outList.unsafeMutablePointer)
        return (L, R)
    }

    static func dspTests() -> Never {
        var fails = 0
        func check(_ name: String, _ got: Float, _ want: Float, tol: Float = 0.6) {
            let g = 20 * log10f(max(got, 1e-9))
            let ok = abs(g - want) <= tol
            if !ok { fails += 1 }
            print(String(format: "%@  %-46@ got %6.1f dB, want %6.1f", ok ? "PASS" : "FAIL", name as NSString, g, want))
        }
        func fresh() -> DSP { DSP() }

        var d = fresh(); d.mediaGain = 2
        check("volume 200% (+6 dB)", measure(d, media: (1000, 0.01)).0, -40 + 6.02)
        d = fresh(); d.bassDB = 12
        check("bass +12 dB at 50 Hz", measure(d, media: (50, 0.01)).0, -40 + 11.5, tol: 1.0)
        d = fresh(); d.bassDB = 12
        check("bass leaves 3 kHz alone", measure(d, media: (3000, 0.01)).0, -40, tol: 0.5)
        d = fresh(); d.mediaGain = 3
        check("limiter holds −1 dBFS (−6 dBFS × 300%)", measure(d, media: (1000, 0.5)).0, -1.0, tol: 0.1)
        d = fresh(); d.night = true
        let loud = measure(d, media: (1000, 0.5)).0
        d = fresh(); d.night = true
        let quiet = measure(d, media: (1000, 0.01)).0
        let spread = 20 * log10f(loud) - 20 * log10f(quiet)
        print(String(format: "%@  %-46@ loud−quiet spread %.1f dB (input 34 dB)", spread < 20 ? "PASS" : "FAIL", "Night Mode squeezes loud vs quiet" as NSString, spread))
        if spread >= 20 { fails += 1 }
        d = fresh(); d.mediaFade = 0
        check("sleep fade: media silent, call kept", measure(d, media: (1000, 0.3), call: (440, 0.05), seconds: 60).0, -26.0, tol: 0.5)
        d = fresh(); d.callGain = 1.5
        check("call voice 150% (+3.5 dB), media muted", measure(d, media: (1000, 0), call: (440, 0.05)).0, -26.0 + 3.52)
        d = fresh(); d.mediaGain = 2; d.bassDB = 12
        check("bass/volume don't touch the call bus", measure(d, media: (1000, 0), call: (60, 0.05)).0, -26.0)

        // Effects
        func last(_ x: [Float]) -> ArraySlice<Float> { x[(x.count / 2)...] }
        func fxdsp(_ set: (DSP) -> Void) -> DSP { let d = DSP(); d.fxOn = true; set(d); return d }
        func checkGT(_ name: String, _ a: Float, _ b: Float, by: Float) {
            let ok = a - b >= by; if !ok { fails += 1 }
            print(String(format: "%@  %-46@ %.1f dB vs %.1f dB (need %.0f dB apart)", ok ? "PASS" : "FAIL", name as NSString, a, b, by))
        }
        var o = render(fxdsp { $0.fxSemitones = 3 }, freq: 440, amp: 0.1, seconds: 2)
        let spedHz = 440 * pow(2, 3.0 / 12)
        checkGT("Sped up +3: 440 Hz moves to 523 Hz", tone(last(o), spedHz), tone(last(o), 440), by: 20)
        o = render(fxdsp { $0.fxSemitones = -3 }, freq: 1000, amp: 0.1, seconds: 2)
        let slowedHz = 1000 * pow(2, -3.0 / 12)
        checkGT("Slowed −3: 1000 Hz moves to 841 Hz", tone(last(o), slowedHz), tone(last(o), 1000), by: 20)
        o = render(fxdsp { $0.fxHarmony = 0.6 }, freq: 1000, amp: 0.1, seconds: 2)
        checkGT("Harmony adds the octave (2000 Hz)", tone(last(o), 2000), -80, by: 40)
        o = render(fxdsp { $0.fxReverb = 0.5; $0.fxRoom = 0.8 }, freq: 0, amp: 0.8, seconds: 2)
        let tail = o[(48000 / 2)..<(48000)].map { $0 * $0 }.reduce(0, +)
        let tailDB = 10 * log10f(max(tail / 24000, 1e-12))
        checkGT("Reverb leaves a tail 0.5–1 s after a click", tailDB, -120, by: 40)
        o = render(fxdsp { $0.fxSemitones = -3; $0.fxReverb = 0.5; $0.fxHarmony = 0.5 }, freq: 1000, amp: 0, seconds: 2, call: (440, 0.05))
        check("effects never touch the call voice", tone(last(o), 440) == 0 ? 1e-9 : powf(10, tone(last(o), 440) / 20), -26.0, tol: 0.3)
        o = render(fxdsp { $0.fxReverb = 1; $0.fxRoom = 1; $0.fxHarmony = 1; $0.fxSemitones = 4; $0.fxWidth = 2 }, freq: 200, amp: 0.9, seconds: 3)
        let pk = o.map { abs($0) }.max() ?? 0
        let finite = o.allSatisfy { $0.isFinite }
        print(String(format: "%@  %-46@ peak %.2f dBFS", (pk <= 0.8913 && finite) ? "PASS" : "FAIL", "everything maxed: no clipping, no blow-up" as NSString, 20 * log10f(pk)))
        if !(pk <= 0.8913 && finite) { fails += 1 }

        // Studio Master
        func sm(_ amt: Float) -> DSP { let d = DSP(); d.studioAmount = amt; return d }
        func lvl(_ d: DSP, _ f: Double, at: Double? = nil) -> Float { let o = render(d, freq: f, amp: 0.05, seconds: 2); return tone(last(o), at ?? f) }
        checkGT("Studio: harmonic bass adds 100 Hz to a 50 Hz note", lvl(sm(1), 50, at: 100), lvl(sm(0), 50, at: 100), by: 30)
        check("Studio: 50 Hz note itself kept", powf(10, lvl(sm(1), 50) / 20), -26 + 1.0, tol: 2.5)
        checkGT("Studio: cuts sub-sonic rumble at 12 Hz", lvl(sm(0), 12), lvl(sm(1), 12), by: 5)
        check("Studio: de-mud dip at 320 Hz", powf(10, lvl(sm(1), 320) / 20), -26 - 2.5, tol: 0.8)
        check("Studio: air shelf at 14 kHz", powf(10, lvl(sm(1), 14000) / 20), -26 + 3.4, tol: 1.0)
        check("Studio: 1 kHz (vocals) left natural", powf(10, lvl(sm(1), 1000) / 20), -26, tol: 0.7)
        do {
            let d = sm(1); d.fxOn = true; d.fxReverb = 1; d.fxRoom = 1; d.fxHarmony = 1; d.fxSemitones = 4; d.fxWidth = 2
            d.bassDB = 12; d.mediaGain = 3
            let o = render(d, freq: 60, amp: 0.9, seconds: 3)
            let pk = o.map { abs($0) }.max() ?? 0
            let ok = pk <= 0.8913 && o.allSatisfy { $0.isFinite }
            if !ok { fails += 1 }
            print(String(format: "%@  %-46@ peak %.2f dBFS", ok ? "PASS" : "FAIL", "Studio + all effects + 300% + bass maxed" as NSString, 20 * log10f(pk)))
            let c = sm(1); let co = render(c, freq: 0, amp: 0, seconds: 2, call: (440, 0.05))
            check("Studio never touches the call voice", powf(10, tone(last(co), 440) / 20), -26.0, tol: 0.3)
        }

        // 8D audio (one circle = 4 s in the test: front → right → behind → left)
        do {
            func w(_ x: [Float], _ t: Double) -> ArraySlice<Float> { x[Int((t - 0.05) * 48000)..<Int((t + 0.05) * 48000)] }
            let d = DSP(); d.eightDOn = true; d.eightDSeconds = 4
            let (L, R) = renderLR(d, freq: 1000, amp: 0.1, seconds: 4)
            checkGT("8D: at 1 s the music is on your right", tone(w(R, 1), 1000), tone(w(L, 1), 1000), by: 20)
            checkGT("8D: at 3 s the music is on your left", tone(w(L, 3), 1000), tone(w(R, 3), 1000), by: 20)
            let backL = tone(w(L, 2), 1000), backR = tone(w(R, 2), 1000)
            let ok = abs(backL - backR) < 1.5 && backL < -20.5 && backL > -24
            if !ok { fails += 1 }
            print(String(format: "%@  %-46@ L %.1f / R %.1f dB (centred, a bit quieter)", ok ? "PASS" : "FAIL", "8D: at 2 s it's behind you" as NSString, backL, backR))
            let c = DSP(); c.eightDOn = true; c.eightDSeconds = 4
            let (cl, cr) = renderLR(c, freq: 1000, amp: 0, seconds: 4, call: (440, 0.05))
            let callOK = abs(tone(w(cl, 1), 440) - tone(w(cr, 1), 440)) < 0.1 && abs(tone(w(cl, 1), 440) + 26) < 0.3
            if !callOK { fails += 1 }
            print(String(format: "%@  %-46@ L %.1f / R %.1f dB", callOK ? "PASS" : "FAIL", "8D: call voice stays centred" as NSString, tone(w(cl, 1), 440), tone(w(cr, 1), 440)))
            let m = DSP(); m.eightDOn = true; m.eightDSeconds = 4; m.studioAmount = 1; m.mediaGain = 3; m.bassDB = 12
            let (ml, mr) = renderLR(m, freq: 80, amp: 0.9, seconds: 4)
            let pk = max(ml.map { abs($0) }.max() ?? 0, mr.map { abs($0) }.max() ?? 0)
            let clipOK = pk <= 0.8913 && ml.allSatisfy { $0.isFinite }
            if !clipOK { fails += 1 }
            print(String(format: "%@  %-46@ peak %.2f dBFS", clipOK ? "PASS" : "FAIL", "8D + Studio + 300% + bass: no clipping" as NSString, 20 * log10f(pk)))
        }
        print(fails == 0 ? "ALL DSP CHECKS PASSED" : "\(fails) DSP CHECK(S) FAILED")
        exit(fails == 0 ? 0 : 1)
    }

    // MARK: live engine (taps only the given processes)

    static func engineTest(_ a: [String]) -> Never {
        guard let m = CA.processObject(pid: pid_t(a[2])!) else { print("no audio process for media pid"); exit(2) }
        let e = AudioEngine()
        e.onlyProcesses = [m]
        if let cp = pid_t(a[3]), cp != 0 {
            guard let c = CA.processObject(pid: cp) else { print("no audio process for call pid"); exit(2) }
            e.testCallProcesses = [c]
        }
        e.outputOverrideUID = a[4]
        e.gainPercent = Double(a[5])!; e.bassDB = Double(a[6])!
        e.setOn(true)
        guard e.running else { print("engine failed: \(e.lastError ?? "?")"); exit(3) }
        var t = 0.0, mp: Float = 0, cp: Float = 0, op: Float = 0
        while t < Double(a[7])! {
            RunLoop.main.run(until: Date().addingTimeInterval(0.25)); t += 0.25
            if t > 0.75 { mp = max(mp, e.dsp.mediaPeak); cp = max(cp, e.dsp.callPeak); op = max(op, e.dsp.outPeak) }
        }
        print("on \(e.outputName) sr=\(e.dsp.sampleRate) inputBuffers=\(e.dsp.inputBufferCount) tapOffset=\(e.dsp.tapOffset) tapChannels=\(e.dsp.firstTapChannels) callBus=\(e.dsp.hasCallBus)")
        print("blocks=\(e.dsp.blocks) media=\(db(mp)) call=\(db(cp)) out=\(db(op)) dBFS")
        e.setOn(false)
        exit(0)
    }

    static func micTest(_ a: [String]) -> Never {
        let m = MicLock(); m.onlyUIDs = [a[2]]
        m.onBlocked = { print("blocked an unmute on \($0)"); fflush(stdout) }
        m.setOn(true); print("locked"); fflush(stdout)
        RunLoop.main.run(until: Date().addingTimeInterval(Double(a[3])!))
        print("blocked unmutes: \(m.blockedUnmutes)")
        m.setOn(false); print("released"); exit(0)
    }

    // MARK: README screenshot

    @MainActor
    static func shot(_ a: [String]) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let dark = a.count < 4 || a[3] != "light"
        app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let state = AppState.demo()

        guard let screen = NSScreen.main else { exit(1) }
        let vf = screen.visibleFrame
        let frame = NSRect(x: vf.midX - 250, y: vf.maxY - 790, width: 500, height: 780)
        let backdrop = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        backdrop.level = .floating
        backdrop.isOpaque = true
        backdrop.contentView = NSImageView(image: wallpaper(size: frame.size, dark: dark))
        backdrop.orderFrontRegardless()

        let ctl = StatusController(state: state)
        ctl.open(at: NSPoint(x: frame.midX, y: frame.maxY - 30), autoClose: false)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            let top = screen.frame.maxY - frame.maxY
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-x", "-o", "-R\(Int(frame.minX)),\(Int(top)),\(Int(frame.width)),\(Int(frame.height))", a[2]]
            try? p.run(); p.waitUntilExit()
            print("saved \(a[2])")
            exit(0)
        }
        app.run()
        exit(0)
    }

    /// A soft, colourful backdrop so the glass has something to refract.
    static func wallpaper(size: NSSize, dark: Bool) -> NSImage {
        NSImage(size: size, flipped: false) { r in
            let base = NSGradient(colors: dark
                ? [NSColor(red: 0.05, green: 0.06, blue: 0.16, alpha: 1), NSColor(red: 0.16, green: 0.07, blue: 0.30, alpha: 1)]
                : [NSColor(red: 0.80, green: 0.86, blue: 1.0, alpha: 1), NSColor(red: 0.98, green: 0.84, blue: 0.92, alpha: 1)])!
            base.draw(in: r, angle: -60)
            let blobs: [(CGFloat, CGFloat, CGFloat, NSColor)] = [
                (0.15, 0.80, 300, NSColor(red: 0.20, green: 0.55, blue: 1.0, alpha: dark ? 0.75 : 0.55)),
                (0.95, 0.55, 280, NSColor(red: 1.0, green: 0.35, blue: 0.55, alpha: dark ? 0.65 : 0.45)),
                (0.30, 0.15, 320, NSColor(red: 0.55, green: 0.30, blue: 1.0, alpha: dark ? 0.7 : 0.45)),
                (0.85, 0.05, 220, NSColor(red: 1.0, green: 0.66, blue: 0.20, alpha: dark ? 0.55 : 0.45)),
            ]
            for (x, y, rad, c) in blobs {
                let g = NSGradient(colors: [c, c.withAlphaComponent(0)])!
                g.draw(fromCenter: NSPoint(x: r.width * x, y: r.height * y), radius: 0,
                       toCenter: NSPoint(x: r.width * x, y: r.height * y), radius: rad, options: [])
            }
            return true
        }
    }
}
