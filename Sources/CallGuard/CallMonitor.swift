import AppKit
import Carbon.HIToolbox
import CoreAudio
import CoreGraphics

/// Watches which apps are using a microphone (= on a call) and how long you've been idle.
final class CallMonitor {
    private(set) var micUsers: [String] = []
    private(set) var callStart: Date?
    var onChange: (() -> Void)?
    private var timer: Timer?

    func start() {
        poll()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func poll() {
        let me = getpid()
        let names = Array(Set(CA.processObjects.filter { CA.pid(of: $0) != me && CA.isRunningInput($0) }
            .map(CA.appName(of:)))).sorted()
        guard names != micUsers else { return }
        let wasOnCall = !micUsers.isEmpty
        micUsers = names
        if names.isEmpty { callStart = nil } else if !wasOnCall { callStart = Date() }
        onChange?()
    }

    var onCall: Bool { !micUsers.isEmpty }

    /// Seconds since the last keyboard, mouse or trackpad input (no permission needed).
    static var idleSeconds: Double {
        let any = CGEventType(rawValue: UInt32.max) ?? .mouseMoved
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
    }
}

/// System-wide shortcuts through Carbon hot keys: they need no Accessibility permission.
///  ⌃⌥M  lock / unlock the mic
///  ⌃⌥T  hold to talk while the mic is locked
final class Hotkeys {
    nonisolated(unsafe) static var shared: Hotkeys?
    var onToggleLock: (() -> Void)?
    var onTalk: ((Bool) -> Void)?
    private(set) var registered: [String: Bool] = [:]
    private var refs: [EventHotKeyRef?] = []
    private var handler: EventHandlerRef?

    static let lockLabel = "⌃⌥M"
    static let talkLabel = "⌃⌥T"

    init() {
        Hotkeys.shared = self
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            let id = hk.id
            DispatchQueue.main.async { Hotkeys.shared?.handle(id: id, pressed: pressed) }
            return noErr
        }, 2, &types, nil, &handler)
        registered["lock"] = register(id: 1, key: UInt32(kVK_ANSI_M), mods: UInt32(controlKey | optionKey))
        registered["talk"] = register(id: 2, key: UInt32(kVK_ANSI_T), mods: UInt32(controlKey | optionKey))
    }

    private func register(id: UInt32, key: UInt32, mods: UInt32) -> Bool {
        var ref: EventHotKeyRef?
        let st = RegisterEventHotKey(key, mods, EventHotKeyID(signature: OSType(0x4347_4844), id: id),
                                     GetApplicationEventTarget(), 0, &ref)
        refs.append(ref)
        return st == noErr
    }

    private func handle(id: UInt32, pressed: Bool) {
        if id == 1, pressed { onToggleLock?() }
        if id == 2 { onTalk?(pressed) }
    }
}
