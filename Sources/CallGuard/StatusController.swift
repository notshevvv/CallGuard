import AppKit
import SwiftUI

/// A borderless floating panel that can take clicks without stealing focus from your apps.
final class GlassPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil); onClose?() }
    var onClose: (() -> Void)?
}

private struct SizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// Wraps the SwiftUI panel so it reports its size (the window follows it, anchored at the top).
struct SizedPanel: View {
    @ObservedObject var s: AppState
    var onSize: (CGSize) -> Void
    var onQuit: () -> Void
    var body: some View {
        PanelView(s: s, maxHeight: ((NSScreen.main?.visibleFrame.height ?? 900) - 24), onQuit: onQuit)
            .fixedSize()
            .background(GeometryReader { g in Color.clear.preference(key: SizeKey.self, value: g.size) })
            .onPreferenceChange(SizeKey.self) { size in onSize(size) }
    }
}

/// The menu bar icon and the glass panel under it.
@MainActor
final class StatusController: NSObject {
    let state: AppState
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let panel: GlassPanel
    private var hosting: NSHostingView<SizedPanel>!
    private var clickMonitor: Any?
    private var size = CGSize(width: 372, height: 600)
    private var anchor: NSPoint?          // top-center of the panel
    private let radius: CGFloat = 26

    init(state: AppState) {
        self.state = state
        panel = GlassPanel(contentRect: NSRect(x: 0, y: 0, width: 372, height: 600),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false   // the glass draws its own soft shadow; a window shadow would be square
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.onClose = { [weak self] in self?.didClose() }

        hosting = NSHostingView(rootView: SizedPanel(s: state, onSize: { [weak self] sz in self?.resize(to: sz) },
                                                     onQuit: { NSApp.terminate(nil) }))
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear

        // The panel's own surface: Liquid Glass on macOS 26+, a vibrant material before that.
        let container: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = radius
            glass.contentView = hosting
            container = glass
        } else {
            let fx = NSVisualEffectView()
            fx.material = .popover
            fx.blendingMode = .behindWindow
            fx.state = .active
            fx.wantsLayer = true
            fx.layer?.cornerRadius = radius
            fx.layer?.masksToBounds = true
            hosting.translatesAutoresizingMaskIntoConstraints = false
            fx.addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: fx.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
                hosting.topAnchor.constraint(equalTo: fx.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: fx.bottomAnchor),
            ])
            container = fx
        }
        container.wantsLayer = true
        container.layer?.cornerRadius = radius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        panel.contentView = container

        if let b = item.button {
            b.target = self
            b.action = #selector(toggle)
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        state.onStatusChange = { [weak self] in self?.updateIcon() }
        updateIcon()
    }

    // MARK: icon

    func updateIcon() {
        guard let b = item.button else { return }
        let locked = state.micLocked, talking = state.talking
        let name = talking ? "mic.fill" : (locked ? "mic.slash.fill" : (state.engineRunning ? "mic.and.signal.meter" : "mic"))
        var img = NSImage(systemSymbolName: name, accessibilityDescription: "CallGuard") ?? NSImage()
        if locked || talking {
            let color: NSColor = talking ? .systemGreen : .systemRed
            img = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
                .applying(.init(paletteColors: [color]))) ?? img
            img.isTemplate = false
            b.attributedTitle = NSAttributedString(string: talking ? " LIVE" : " LOCKED", attributes: [
                .foregroundColor: color, .font: NSFont.systemFont(ofSize: 11, weight: .bold)])
        } else {
            img = img.withSymbolConfiguration(.init(pointSize: 14, weight: .regular)) ?? img
            img.isTemplate = true
            b.title = ""
        }
        b.image = img
        b.imagePosition = .imageLeading
        b.toolTip = locked ? "Mic LOCKED. Click to unmute yourself. Right-click for the panel." : "CallGuard"
    }

    // MARK: panel

    /// One click on the red LOCKED icon unmutes you straight away. Right-click opens the panel.
    @objc func toggle() {
        let right = NSApp.currentEvent?.type == .rightMouseUp
        if state.micLocked, !right, !panel.isVisible {
            state.micLocked = false
            updateIcon()
            return
        }
        panel.isVisible ? close() : open()
    }

    func open(at point: NSPoint? = nil, autoClose: Bool = true) {
        if let point { anchor = point }
        else if let b = item.button, let w = b.window {
            let r = w.convertToScreen(b.convert(b.bounds, to: nil))
            anchor = NSPoint(x: r.midX, y: r.minY - 6)
        }
        layout()
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(nil)        // don't auto-focus (and auto-scroll to) a control
        state.scrollToTopToken &+= 1
        state.panelOpen = true
        guard autoClose else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    func close() {
        panel.orderOut(nil)
        didClose()
    }

    private func didClose() {
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        state.panelOpen = false
    }

    private func resize(to s: CGSize) {
        guard s.width > 10, s.height > 10, s != size else { return }
        size = s
        layout()
    }

    private func layout() {
        guard let anchor else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        let vf = screen?.visibleFrame ?? .zero
        let h = min(size.height, vf.height - 12)
        var x = anchor.x - size.width / 2
        x = min(max(x, vf.minX + 8), vf.maxX - size.width - 8)
        panel.setFrame(NSRect(x: x, y: anchor.y - h, width: size.width, height: h), display: true)
    }
}
