import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    var status: StatusController!

    func applicationDidFinishLaunching(_ n: Notification) {
        status = StatusController(state: state)
        state.start()
        status.updateIcon()
    }

    func applicationWillTerminate(_ n: Notification) { state.shutdown() }
}

let args = CommandLine.arguments
if args.count > 1, args[1].hasPrefix("--selftest") || args[1].hasPrefix("--shot") {
    SelfTest.run(args)   // development checks and README screenshots; never returns
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
