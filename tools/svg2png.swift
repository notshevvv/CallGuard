// svg2png <in.svg> <out.png> <width> [height] : renders an SVG with a transparent background using WebKit
import AppKit
import WebKit
let a = CommandLine.arguments
let size = CGFloat(Double(a[3])!)
let height = CGFloat(Double(a.count > 4 ? a[4] : a[3])!)
let svg = try! String(contentsOfFile: a[1], encoding: .utf8)
let app = NSApplication.shared
let win = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: size, height: height), styleMask: .borderless, backing: .buffered, defer: false)
let web = WKWebView(frame: NSRect(x: 0, y: 0, width: size, height: height))
web.setValue(false, forKey: "drawsBackground")
win.contentView = web
win.orderFrontRegardless()
final class D: NSObject, WKNavigationDelegate {
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let cfg = WKSnapshotConfiguration(); cfg.rect = NSRect(x: 0, y: 0, width: size, height: height); cfg.snapshotWidth = NSNumber(value: Double(size))
            w.takeSnapshot(with: cfg) { img, err in
                guard let img, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { print("fail \(String(describing: err))"); exit(1) }
                // force exact pixel size
                let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
                rep.draw(in: NSRect(x: 0, y: 0, width: size, height: height)); NSGraphicsContext.restoreGraphicsState()
                try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2])); exit(0)
            }
        }
    }
}
let d = D(); web.navigationDelegate = d
let html = "<html><head><style>html,body{margin:0;background:transparent}svg{display:block;width:\(Int(size))px;height:\(Int(height))px}</style></head><body>\(svg)</body></html>"
web.loadHTMLString(html, baseURL: nil)
app.run()
