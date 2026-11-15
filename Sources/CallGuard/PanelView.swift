import SwiftUI

// MARK: - Glass helpers (Liquid Glass on macOS 26+, materials before that)

extension View {
    @ViewBuilder
    func glassTile(tint: Color?, radius: CGFloat = 20) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(tint.map { Glass.regular.tint($0.opacity(0.55)).interactive() } ?? Glass.regular.interactive(),
                             in: .rect(cornerRadius: radius))
        } else {
            self.background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(tint.map { AnyShapeStyle($0.opacity(0.35)) } ?? AnyShapeStyle(.thinMaterial)))
        }
    }

    /// Cards sit on the glass panel, so they use a soft fill rather than more glass.
    func card() -> some View {
        self.padding(12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.primary.opacity(0.055))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)))
    }

    @ViewBuilder
    func glassButtonStyle() -> some View {
        if #available(macOS 26.0, *) { self.buttonStyle(.glass) } else { self.buttonStyle(.bordered) }
    }
}

enum Palette {
    static let lock = Color(red: 1.0, green: 0.27, blue: 0.23)
    static let duck = Color(red: 0.17, green: 0.62, blue: 1.0)
    static let hifi = Color(red: 0.69, green: 0.38, blue: 1.0)
    static let sound = Color(red: 1.0, green: 0.58, blue: 0.16)
    static let sleep = Color(red: 0.42, green: 0.45, blue: 1.0)
    static let live = Color(red: 0.2, green: 0.84, blue: 0.4)
}

// MARK: - Panel

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct PanelView: View {
    @ObservedObject var s: AppState
    var maxHeight: CGFloat = 820
    var onQuit: () -> Void = { NSApp.terminate(nil) }
    @State private var showAllLog = false
    @State private var contentHeight: CGFloat = 640

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            content.background(GeometryReader { g in
                Color.clear.preference(key: ContentHeightKey.self, value: g.size.height)
            })
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 372, height: min(max(contentHeight, 200), maxHeight))
        .onPreferenceChange(ContentHeightKey.self) { h in if h > 0 { contentHeight = h } }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            tiles
            if s.micLocked { lockStrip.transition(.move(edge: .top).combined(with: .opacity)) }
            soundCard
            sleepCard
            activity
            footer
        }
        .padding(14)
        .frame(width: 372)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: s.micLocked)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: s.boostOn)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: s.callApps)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: showAllLog)
        .animation(.easeInOut(duration: 0.25), value: s.mediaFaded)
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("CallGuard").font(.system(size: 15, weight: .semibold))
                callLine
            }
            Spacer()
            Menu {
                Toggle("Start at login", isOn: Binding(get: { s.launchAtLogin }, set: { s.setLaunchAtLogin($0) }))
                Divider()
                Text("Shortcuts: \(Hotkeys.lockLabel) lock · hold \(Hotkeys.talkLabel) to talk")
                Divider()
                Button("Quit CallGuard", action: onQuit)
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .glassTile(tint: nil, radius: 14)
        }
    }

    @ViewBuilder private var callLine: some View {
        if let start = s.callStart, let app = s.callApps.first {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                HStack(spacing: 5) {
                    Circle().fill(Palette.live).frame(width: 7, height: 7)
                        .shadow(color: Palette.live.opacity(0.8), radius: 3)
                    Text("On a call · \(app) · \(Self.duration(ctx.date.timeIntervalSince(start)))")
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
        } else {
            Text("No call right now").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    static func duration(_ t: TimeInterval) -> String {
        let s = Int(max(t, 0)); let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    // MARK: big toggles

    @ViewBuilder private var tiles: some View {
        let row = HStack(spacing: 10) {
            FeatureTile(title: "Mic Lock", subtitle: lockSubtitle,
                        symbol: s.talking ? "waveform" : (s.micLocked ? "mic.slash.fill" : "mic.fill"),
                        tint: s.talking ? Palette.live : Palette.lock, isOn: s.micLocked) { s.micLocked.toggle() }
            FeatureTile(title: "No Ducking", subtitle: duckSubtitle, symbol: "speaker.wave.3.fill",
                        tint: Palette.duck, isOn: s.stopDucking) { s.stopDucking.toggle() }
            FeatureTile(title: "Hi-Fi Buds", subtitle: hifiSubtitle, symbol: "airpods",
                        tint: Palette.hifi, isOn: s.hifiOn) { s.hifiOn.toggle() }
        }
        if #available(macOS 26.0, *) { GlassEffectContainer(spacing: 10) { row } } else { row }
    }

    private var lockSubtitle: String { s.talking ? "Talking…" : (s.micLocked ? "No one hears you" : "Off") }
    private var duckSubtitle: String {
        guard s.stopDucking else { return "Off" }
        switch s.ducking {
        case .dodged: return "Full volume"
        case .fallback: return "Boosting"
        case .needsHeadphones: return "Needs earbuds"
        default: return s.engineError == nil ? "Ready" : "Needs permission"
        }
    }
    private var hifiSubtitle: String {
        if !s.muffled.isEmpty { return s.hifiOn ? "Fixing…" : "Muffled now" }
        return s.hifiOn ? "Stereo" : "Off"
    }

    private var lockStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: s.talking ? "waveform" : "hand.raised.fill")
                .foregroundStyle(s.talking ? Palette.live : Palette.lock)
                .symbolEffect(.variableColor.iterative, isActive: s.talking)
            Text(s.talking ? "Mic open while you hold \(Hotkeys.talkLabel)" : "Hold \(Hotkeys.talkLabel) to talk · \(Hotkeys.lockLabel) to unlock")
                .font(.system(size: 11.5))
            Spacer()
            Button(s.talking ? "Live" : "Unmute me") { s.micLocked = false }
                .controlSize(.small).glassButtonStyle().tint(Palette.live)
            if s.blockedUnmutes > 0 {
                Text("\(s.blockedUnmutes) blocked")
                    .font(.system(size: 10.5, weight: .semibold)).monospacedDigit()
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Palette.lock.opacity(0.22)))
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.lock.opacity(s.talking ? 0.0 : 0.10)))
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.live.opacity(s.talking ? 0.16 : 0.0)))
    }

    // MARK: sound

    private var soundCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(symbol: "dial.high.fill", title: "Sound boost", tint: Palette.sound) {
                Toggle("", isOn: $s.boostOn).toggleStyle(.switch).controlSize(.small).labelsHidden().tint(Palette.sound)
            }
            LabeledSlider(label: "Volume", value: $s.gain, range: 100...300, step: 5, tint: Palette.sound) { "\(Int($0))%" }
                .disabled(!s.boostOn).opacity(s.boostOn ? 1 : 0.45)
            LabeledSlider(label: "Bass", value: $s.bass, range: 0...12, step: 1, tint: Palette.sound) { $0 < 0.5 ? "Off" : "+\(Int($0)) dB" }
                .disabled(!s.boostOn).opacity(s.boostOn ? 1 : 0.45)
            if s.callViaUs {
                LabeledSlider(label: "Call voice", value: $s.callVolume, range: 50...200, step: 5, tint: Palette.duck) { "\(Int($0))%" }
                    .transition(.opacity)
            }
            ToggleRow(symbol: "moon.fill", title: "Night Mode", detail: "Evens out sudden loud sounds", tint: Palette.sleep, isOn: $s.night)
            Meters(media: s.mediaLevel, call: s.callLevel, showCall: s.callViaUs, active: s.engineRunning)
            if let e = s.engineError {
                Label(e, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
        }
        .card()
    }

    // MARK: sleep

    private var sleepCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(symbol: "moon.zzz.fill", title: "Falling asleep on a call", tint: Palette.sleep) { EmptyView() }
            HStack {
                Text("Fade out media").font(.system(size: 12))
                Spacer()
                Picker("", selection: $s.sleepMinutes) {
                    Text("Off").tag(0); Text("15m").tag(15); Text("30m").tag(30); Text("1h").tag(60); Text("2h").tag(120)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 196)
            }
            if let end = s.sleepEndsAt {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text("Music and videos fade in \(Self.duration(end.timeIntervalSince(ctx.date))). The call voice stays.")
                        .monospacedDigit().contentTransition(.numericText())
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
            } else if s.mediaFaded {
                HStack {
                    Label("Media faded out", systemImage: "moon.stars.fill").font(.system(size: 11.5))
                    Spacer()
                    Button("Restore") { s.restoreMedia() }.controlSize(.small).glassButtonStyle()
                }
            }
            HStack {
                Text("Lock mic when I go quiet").font(.system(size: 12))
                Spacer()
                Picker("", selection: $s.autoLockMinutes) {
                    Text("Never").tag(0); Text("after 5 min").tag(5); Text("after 10 min").tag(10)
                    Text("after 20 min").tag(20); Text("after 30 min").tag(30); Text("after 1 hour").tag(60)
                }
                .labelsHidden().fixedSize()
            }
            ToggleRow(symbol: "lock.open.fill", title: "Unlock mic when the call ends", detail: nil, tint: Palette.lock, isOn: $s.autoUnlock)
        }
        .card()
    }

    // MARK: activity

    private var activity: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button { showAllLog.toggle() } label: {
                HStack {
                    Text("Activity").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(showAllLog ? 180 : 0)).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            ForEach(Array(s.log.prefix(showAllLog ? 12 : 2))) { e in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: e.symbol).font(.system(size: 10.5)).foregroundStyle(.secondary).frame(width: 14)
                    Text(e.text).font(.system(size: 11)).lineLimit(2)
                    Spacer(minLength: 4)
                    Text(e.date, style: .time).font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
            if s.log.isEmpty { Text("Nothing yet").font(.system(size: 11)).foregroundStyle(.tertiary) }
        }
        .card()
    }

    private var footer: some View {
        HStack {
            Toggle("Start at login", isOn: Binding(get: { s.launchAtLogin }, set: { s.setLaunchAtLogin($0) }))
                .toggleStyle(.switch).controlSize(.mini).font(.system(size: 11))
            Spacer()
            Button("Quit", action: onQuit).controlSize(.small).glassButtonStyle()
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Pieces

struct FeatureTile: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let isOn: Bool
    let action: () -> Void
    @State private var bounce = 0

    var body: some View {
        Button { bounce += 1; action() } label: {
            VStack(spacing: 7) {
                ZStack {
                    Circle().fill(isOn ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.primary.opacity(0.09)))
                        .shadow(color: isOn ? tint.opacity(0.55) : .clear, radius: 8, y: 2)
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                        .symbolEffect(.bounce, value: bounce)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 42, height: 42)
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .glassTile(tint: isOn ? tint.opacity(0.35) : nil)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isOn)
    }
}

struct CardTitle<Trailing: View>: View {
    let symbol: String
    let title: String
    let tint: Color
    @ViewBuilder let trailing: () -> Trailing
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.gradient))
            Text(title).font(.system(size: 13, weight: .semibold))
            Spacer()
            trailing()
        }
    }
}

struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let tint: Color
    let format: (Double) -> String
    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 12)).frame(width: 66, alignment: .leading)
            Slider(value: Binding(get: { value }, set: { value = ($0 / step).rounded() * step }), in: range)
                .controlSize(.small).tint(tint)
            Text(format(value)).font(.system(size: 11.5, weight: .medium)).monospacedDigit()
                .foregroundStyle(.secondary).contentTransition(.numericText())
                .frame(width: 46, alignment: .trailing)
        }
    }
}

struct ToggleRow: View {
    let symbol: String
    let title: String
    let detail: String?
    let tint: Color
    @Binding var isOn: Bool
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(isOn ? tint : .secondary).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12))
                if let detail { Text(detail).font(.system(size: 10.5)).foregroundStyle(.secondary) }
            }
            Spacer()
            Toggle("", isOn: $isOn).toggleStyle(.switch).controlSize(.mini).labelsHidden().tint(tint)
        }
    }
}

struct Meters: View {
    let media: Float
    let call: Float
    let showCall: Bool
    let active: Bool
    var body: some View {
        HStack(spacing: 14) {
            bar("Media", media, Palette.sound)
            if showCall { bar("Call", call, Palette.duck) }
        }
        .opacity(active ? 1 : 0.4)
    }
    private func bar(_ name: String, _ v: Float, _ tint: Color) -> some View {
        let db = v > 0 ? 20 * log10(Double(v)) : -60
        let frac = CGFloat(min(max((db + 60) / 60, 0), 1))
        return HStack(spacing: 8) {
            Text(name).font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, g.size.width * frac))
                        .animation(.easeOut(duration: 0.12), value: frac)
                }
            }
            .frame(height: 5)
        }
    }
}
