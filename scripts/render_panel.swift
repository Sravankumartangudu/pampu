// Renders the Mac drop panel in each state, light and dark, for the README.
//   scripts/screenshots.sh  → docs/screenshots/mac-*.png
// Drawn off-screen, so it works with the screen locked or covered.
import AppKit
import SwiftUI

@main
struct Render {
    @MainActor static func main() {
        _ = NSApplication.shared
        let samples = ["/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/iPhone.icns",
                       "/System/Applications/Photos.app", "/System/Applications/Preview.app"].map { URL(fileURLWithPath: $0) }
        let states: [(String, (DropModel) -> Void)] = [
            ("near", { $0.phase = .near; $0.from = "iPhone" }),
            ("swipe", { $0.phase = .near; $0.from = "iPhone"; $0.pull = 0.75 }),
            ("receiving", { m in m.phase = .receiving; m.from = "iPhone"; m.count = 3; m.progress = 0.55; m.current = "IMG_0042.HEIC"
                            m.incoming = samples.map { DropModel.Card(image: NSWorkspace.shared.icon(forFile: $0.path), symbol: "photo") } }),
            ("done", { m in m.phase = .done; m.from = "iPhone"; m.count = 3; m.files = samples
                       m.message = "Saved to ~/Downloads/Pampu/Photos"
                       for u in samples { m.thumbs[u] = NSWorkspace.shared.icon(forFile: u.path) } }),
            ("text", { $0.phase = .text; $0.from = "iPhone"; $0.text = "https://github.com/Sravankumartangudu/pampu"; $0.link = URL(string: "https://github.com/Sravankumartangudu/pampu"); $0.message = "Copied to the clipboard" }),
        ]
        for dark in [false, true] {
            for (name, set) in states {
                let m = DropModel(); set(m)
                let host = NSHostingView(rootView: DropCard(model: m, close: {}).padding(30))
                host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                let size = host.fittingSize
                let win = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
                win.backgroundColor = dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.92, alpha: 1)
                win.appearance = host.appearance
                win.contentView = host
                host.frame = NSRect(origin: .zero, size: size)
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(1.5))   // let the slide-ins and the glow settle
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "docs/screenshots/mac-\(name)\(dark ? "-dark" : "").png"))
            }
        }
    }
}
