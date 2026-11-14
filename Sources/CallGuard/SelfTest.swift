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
