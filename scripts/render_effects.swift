// Renders frames of every drop effect, both halves, off-screen.
//   scripts/effects.sh [dir]   → <dir>/effects-iphone.png  (each effect's throw, mid-flight)
//                                <dir>/effects-mac.png     (each effect's landing in the panel)
//                                <dir>/frames/<effect>-iphone.png, -mac.png  (several moments of each)
import AppKit
import SwiftUI

@main
struct RenderEffects {
    @MainActor static func main() {
        _ = NSApplication.shared
        let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "docs/screenshots")
        let frames = out.appendingPathComponent("frames")
        try? FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)

        // iPhone: a pretend screen with the stack, at one moment of the throw.
        func phone(_ e: DropEffect, at f: Double, label: Bool) -> some View {
            let size = CGSize(width: 260, height: 520)
            let origin = CGPoint(x: size.width / 2, y: size.height - 120)
            let s = f * e.sendDuration
            return ZStack {
                LinearGradient(colors: [Color(red: 0.05, green: 0.08, blue: 0.2), Color(red: 0.12, green: 0.07, blue: 0.28)],
                               startPoint: .top, endPoint: .bottom)
                card.effectMotion(e.send(f)).position(origin)
                EffectCanvas(effect: e, side: .send, start: Date(), origin: origin, frozen: s)
                if label {
                    VStack {
                        Spacer()
                        Text("\(e.emoji) \(e.title)").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                            .padding(.bottom, 16)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }

        func save(_ view: some View, _ url: URL) {
            let r = ImageRenderer(content: view)
            r.scale = 2
            guard let cg = r.cgImage else { print("✗ \(url.lastPathComponent)"); return }
            let rep = NSBitmapImageRep(cgImage: cg)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }

        // The most telling moment of each throw, for the contact sheet.
        let best: [DropEffect: Double] = [.classic: 0.35, .nameDrop: 0.42, .rocket: 0.55, .paperPlane: 0.6, .blackHole: 0.55, .confetti: 0.3,
                                          .fireworks: 0.55, .hyperspace: 0.5, .comet: 0.6, .bubbles: 0.45, .magic: 0.45,
                                          .lightning: 0.12, .portal: 0.55, .shatter: 0.3, .hearts: 0.6, .tornado: 0.45]
        let all = DropEffect.allCases
        save(VStack(spacing: 6) {
            ForEach(0..<(all.count + 3) / 4, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(all[row * 4 ..< min(all.count, row * 4 + 4)]) { e in phone(e, at: best[e] ?? 0.5, label: true) }
                }
            }
        }.padding(6).background(Color.black), out.appendingPathComponent("effects-iphone.png"))

        for e in all {
            save(HStack(spacing: 4) {
                ForEach([0.1, 0.25, 0.4, 0.55, 0.7, 0.9], id: \.self) { f in phone(e, at: f, label: false) }
            }.background(Color.black), frames.appendingPathComponent("\(e.rawValue)-iphone.png"))
        }

        // Mac: the panel with cards landing, drawn through an NSHostingView so materials render.
        let samples = ["/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/iPhone.icns",
                       "/System/Applications/Photos.app", "/System/Applications/Preview.app"]
        func mac(_ e: DropEffect, at f: Double) -> NSImage? {
            let m = DropModel()
            m.phase = .receiving; m.from = "iPhone"; m.count = 3; m.progress = 0.2; m.current = "IMG_0042.HEIC"
            m.incoming = samples.map { DropModel.Card(image: NSWorkspace.shared.icon(forFile: $0), symbol: "photo") }
            m.effect = e; m.landing = true; m.frozen = f * e.arriveDuration
            let host = NSHostingView(rootView: DropCard(model: m, close: {}).padding(12))
            host.appearance = NSAppearance(named: .darkAqua)
            let size = host.fittingSize
            let win = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
            win.backgroundColor = NSColor(white: 0.12, alpha: 1)
            win.appearance = host.appearance
            win.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))   // let the slot positions settle
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
            host.cacheDisplay(in: host.bounds, to: rep)
            let img = NSImage(size: size)
            img.addRepresentation(rep)
            return img
        }

        let macBest: [DropEffect: Double] = [.classic: 0.25, .nameDrop: 0.38, .lightning: 0.2, .paperPlane: 0.4, .shatter: 0.3, .comet: 0.3,
                                             .bubbles: 0.5, .fireworks: 0.4, .confetti: 0.35]
        var sheet: [(DropEffect, NSImage)] = []
        for e in all {
            if let img = mac(e, at: macBest[e] ?? 0.3) { sheet.append((e, img)) }
            let strip = [0.1, 0.3, 0.5, 0.8].compactMap { mac(e, at: $0) }
            save(HStack(spacing: 4) { ForEach(strip.indices, id: \.self) { Image(nsImage: strip[$0]) } }.background(Color.black),
                 frames.appendingPathComponent("\(e.rawValue)-mac.png"))
        }
        save(VStack(alignment: .leading, spacing: 4) {
            ForEach(0..<(sheet.count + 2) / 3, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(sheet[row * 3 ..< min(sheet.count, row * 3 + 3)].indices, id: \.self) { i in
                        Image(nsImage: sheet[i].1)
                            .overlay(alignment: .bottomTrailing) {
                                Text("\(sheet[i].0.emoji) \(sheet[i].0.title)").font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white).padding(4)
                                    .background(Capsule().fill(.black.opacity(0.5))).padding(16)
                            }
                    }
                }
            }
        }.background(Color(white: 0.12)), out.appendingPathComponent("effects-mac.png"))
        print("✓ rendered to \(out.path)")
    }

    static var card: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.56, blue: 1), Color(red: 0.42, green: 0.3, blue: 0.9)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 40, weight: .semibold)).foregroundStyle(.white)
        }
        .frame(width: 100, height: 100)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.9), lineWidth: 3))
    }
}
