// pageshot <file.html> <out.png> <width> <height> [js]
// Renders a local page in WebKit (scripts and web fonts included), optionally runs JS, then snapshots it.
import AppKit
import WebKit
let a = CommandLine.arguments
let file = URL(fileURLWithPath: a[1]); let out = a[2]
let w = CGFloat(Double(a[3])!), h = CGFloat(Double(a[4])!)
let js = a.count > 5 ? a[5] : ""
let app = NSApplication.shared
let win = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: w, height: h), styleMask: .borderless, backing: .buffered, defer: false)
let web = WKWebView(frame: NSRect(x: 0, y: 0, width: w, height: h))
win.contentView = web; win.orderFrontRegardless()
final class D: NSObject, WKNavigationDelegate {
  func webView(_ v: WKWebView, didFinish n: WKNavigation!) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
      v.evaluateJavaScript(js.isEmpty ? "0" : js) { _, err in
        if let err { print("js error: \(err)") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
          let cfg = WKSnapshotConfiguration(); cfg.rect = NSRect(x: 0, y: 0, width: w, height: h)
          v.takeSnapshot(with: cfg) { img, e in
            guard let img, let t = img.tiffRepresentation, let r = NSBitmapImageRep(data: t) else { print("fail \(String(describing: e))"); exit(1) }
            try! r.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out)); print("saved \(out)"); exit(0)
          }
        }
      }
    }
  }
}
let d = D(); web.navigationDelegate = d
web.loadFileURL(file, allowingReadAccessTo: file.deletingLastPathComponent())
app.run()
