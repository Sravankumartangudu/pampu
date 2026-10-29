import AppKit
import SwiftUI
import QuickLookThumbnailing

/// The little card that drops down under the menu bar (by the notch) while an iPhone is close or
/// sending — a glow wave rolls out of the top edge, then thumbnails of what landed.
final class DropPanel {
    static let shared = DropPanel()

    private let model = DropModel()
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    // MARK: What the receiver tells it

    func near(from: String) {
        guard model.phase == .hidden || model.phase == .near else { return }
        model.phase = .near
        model.from = from
        model.wave += 1
        show(hideAfter: 4)
    }

    func far() {
        if model.phase == .near { hide() }
    }

    func begin(from: String, count: Int, names: [String]) {
        model.phase = .receiving
        model.from = from
        model.count = count
        model.progress = 0
        model.current = names.first ?? ""
        model.files = []
        model.thumbs = [:]
        model.message = ""
        model.wave += 1
        show(hideAfter: nil)
    }

    func progress(_ fraction: Double, current: String, from: String) {
        if model.phase != .receiving { begin(from: from, count: 0, names: [current]) }
        model.progress = fraction
        model.current = SafeName.clean(current)
    }

    func done(files: [URL], from: String) {
        model.phase = .done
        model.from = from
        model.files = files
        model.count = files.count
        model.progress = 1
        model.message = folderLabel(files)
        for url in files.prefix(4) { thumbnail(url) }
        show(hideAfter: 7)
    }

    func text(_ text: String, link: URL?, from: String) {
        model.phase = .text
        model.from = from
        model.text = text
        model.link = link
        model.wave += 1
        show(hideAfter: 7)
    }

    func failed(_ message: String) {
        model.phase = .failed
        model.message = message
        show(hideAfter: 8)
    }

    // MARK: Window

    private func show(hideAfter seconds: Double?) {
        let p = panel ?? makePanel()
        panel = p
        place(p)
        if !p.isVisible {
            p.alphaValue = 0
            p.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.18; p.animator().alphaValue = 1 }
        }
        hideWork?.cancel()
        if let seconds { scheduleHide(seconds) }
    }

    private func scheduleHide(_ seconds: Double) {
        let work = DispatchWorkItem { [weak self] in
            guard let self, let p = self.panel else { return }
            // Keep it while the pointer rests on it.
            if p.frame.contains(NSEvent.mouseLocation) { self.scheduleHide(2); return }
            self.hide()
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        guard let p = panel, p.isVisible else { model.phase = .hidden; return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; p.animator().alphaValue = 0 }) {
            p.orderOut(nil)
            self.model.phase = .hidden
        }
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 120),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovable = false
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let host = NSHostingView(rootView: DropCard(model: model, close: { [weak self] in self?.hide() }))
        host.sizingOptions = [.intrinsicContentSize]
        p.contentView = host
        model.onResize = { [weak self] in
            guard let self, let p = self.panel else { return }
            self.place(p)
        }
        return p
    }

    /// Centred just under the menu bar, on the screen with the menu bar.
    private func place(_ p: NSPanel) {
        guard let screen = NSScreen.screens.first, let view = p.contentView else { return }
        let size = view.fittingSize
        let vf = screen.visibleFrame
        p.setFrame(NSRect(x: vf.midX - size.width / 2, y: vf.maxY - size.height - 6, width: size.width, height: size.height),
                   display: true)
    }

    private func folderLabel(_ files: [URL]) -> String {
        let dirs = Set(files.map { $0.deletingLastPathComponent().path })
        let home = NSHomeDirectory()
        let shown = dirs.count == 1 ? dirs.first! : Prefs.shared.folder.path
        return "Saved to " + (shown.hasPrefix(home) ? "~" + shown.dropFirst(home.count) : shown)
    }

    private func thumbnail(_ url: URL) {
        let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 120, height: 120),
                                               scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .all)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { [weak self] rep, _ in
            let image = rep?.nsImage ?? NSWorkspace.shared.icon(forFile: url.path)
            DispatchQueue.main.async { self?.model.thumbs[url] = image }
        }
    }
}

// MARK: - SwiftUI card

final class DropModel: ObservableObject {
    enum Phase { case hidden, near, receiving, done, text, failed }
    @Published var phase: Phase = .hidden { didSet { if phase != oldValue { DispatchQueue.main.async { self.onResize?() } } } }
    @Published var from = ""
    @Published var count = 0
    @Published var progress = 0.0
    @Published var current = ""
    @Published var files: [URL] = []
    @Published var thumbs: [URL: NSImage] = [:]
    @Published var message = ""
    @Published var text = ""
    @Published var link: URL?
    @Published var wave = 0
    var onResize: (() -> Void)?
}

struct DropCard: View {
    @ObservedObject var model: DropModel
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            switch model.phase {
            case .receiving:
                ProgressView(value: model.progress)
                    .tint(Color.accentDrop)
                Text(model.current).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            case .done:
                thumbs
                HStack {
                    Text(model.message).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if model.files.count == 1 {
                        Button("Open") { NSWorkspace.shared.open(model.files[0]); close() }
                    }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(model.files); close() }
                        .buttonStyle(.borderedProminent).tint(Color.accentDrop)
                }
                .controlSize(.small)
            case .text:
                Text(model.text).font(.callout).lineLimit(3).truncationMode(.tail)
                    .textSelection(.enabled)
                HStack {
                    Text("Copied to the clipboard").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if let link = model.link {
                        Button("Open Link") { NSWorkspace.shared.open(link); close() }
                            .buttonStyle(.borderedProminent).tint(Color.accentDrop)
                    }
                }
                .controlSize(.small)
            case .failed:
                Text(model.message).font(.callout).foregroundStyle(.secondary).lineLimit(3)
            case .near, .hidden:
                EmptyView()
            }
        }
        .padding(14)
        .frame(width: 380, alignment: .leading)
        .background {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.regularMaterial)
                Wave(trigger: model.wave)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.18)))
        .onTapGesture { if model.phase == .near || model.phase == .failed { close() } }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.accentDrop)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var icon: String {
        switch model.phase {
        case .near: return "iphone.radiowaves.left.and.right"
        case .receiving: return "arrow.down.circle"
        case .done: return "checkmark.circle.fill"
        case .text: return model.link == nil ? "doc.on.clipboard" : "link"
        case .failed: return "exclamationmark.triangle"
        case .hidden: return "iphone"
        }
    }

    private var title: String {
        switch model.phase {
        case .near: return "\(model.from) is close"
        case .receiving: return model.count > 1 ? "Receiving \(model.count) items" : "Receiving"
        case .done: return model.count == 1 ? "Received 1 item" : "Received \(model.count) items"
        case .text: return model.link == nil ? "Text received" : "Link received"
        case .failed: return "Something went wrong"
        case .hidden: return ""
        }
    }

    private var subtitle: String {
        switch model.phase {
        case .near: return "Hold it there to drop what’s waiting in \(Brand.name)"
        case .receiving, .done, .text: return "from \(model.from)"
        case .failed: return Brand.name
        case .hidden: return ""
        }
    }

    private var thumbs: some View {
        HStack(spacing: 8) {
            ForEach(model.files.prefix(4), id: \.self) { url in
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                    if let image = model.thumbs[url] {
                        Image(nsImage: image).resizable().scaledToFill()
                    }
                }
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .help(url.lastPathComponent)
                .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
            }
            if model.files.count > 4 {
                Text("+\(model.files.count - 4)").font(.headline).foregroundStyle(.secondary).frame(width: 40)
            }
        }
    }
}

/// The glow that rolls down from the top edge, like NameDrop's.
struct Wave: View {
    var trigger: Int
    @State private var t: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            Ellipse()
                .fill(RadialGradient(colors: [Color.accentDrop.opacity(0.75), Color.accentDrop2.opacity(0.35), .clear],
                                     center: .center, startRadius: 0, endRadius: w * 0.55))
                .frame(width: w * (0.3 + t * 1.4), height: 60 + t * 220)
                .position(x: w / 2, y: -20 + t * 40)
                .opacity(Double(1 - t))
                .blur(radius: 12)
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) {
            t = 0
            withAnimation(.easeOut(duration: 1.3)) { t = 1 }
        }
        .onAppear {
            t = 0
            withAnimation(.easeOut(duration: 1.3)) { t = 1 }
        }
    }
}

extension Color {
    static let accentDrop = Color(red: 0.16, green: 0.56, blue: 1.0)
    static let accentDrop2 = Color(red: 0.55, green: 0.36, blue: 0.98)
}
