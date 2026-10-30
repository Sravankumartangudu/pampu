import AppKit
import SwiftUI
import QuickLookThumbnailing

/// The little card that slides down out of the menu bar (by the notch) while an iPhone is close or
/// sending. Ghost cards follow the iPhone's swipe into their slots; when it's let go, the real
/// thumbnails slide in, then what landed. Swipe the card up (or click it while it's waiting) to put it away.
final class DropPanel {
    static let shared = DropPanel()

    private let model = DropModel()
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    /// Bumped on every show and hide, so a fade-out that's overtaken doesn't close the panel.
    private var generation = 0
    /// You swiped the panel away mid-drop: stay out of the way until it's done.
    private var tucked = false
    /// When the landing effect playing now finishes; what landed waits for it.
    private var landingEnds = Date.distantPast

    // MARK: What the receiver tells it

    func near(from: String) {
        guard model.phase == .hidden || model.phase == .near else { return }
        if model.phase == .hidden { model.pull = 0; model.incoming = [] }
        model.phase = .near
        model.from = from
        model.wave += 1
        show(hideAfter: 4)
    }

    func far() {
        if model.phase == .near && model.pull == 0 { hide() }
    }

    /// The iPhone's stack is being swiped up (0…1). Works at any distance, so it can open the panel too.
    func pull(_ f: Double, from: String) {
        guard model.phase == .hidden || model.phase == .near else { return }
        if model.phase == .hidden {
            guard f > 0.02 else { return }
            near(from: from)
        }
        if f >= 1 && model.pull < 1 { model.wave += 1 }   // far enough: the wave of light rolls
        model.pull = f
        hideWork?.cancel()
        if f == 0 { scheduleHide(3) }
    }

    /// The stack was let go: its cards land, with the effect the iPhone threw them with, before the
    /// first byte arrives.
    func fling(from: String, count: Int, cards: [DropModel.Card], effect thrown: DropEffect) {
        let choice = Prefs.shared.landing
        let effect = choice == "match" ? thrown : DropEffect.resolve(choice, after: model.effect)
        tucked = false
        model.effect = effect
        model.flungAt = Date()
        model.landing = true
        landingEnds = model.flungAt.addingTimeInterval(effect.arriveDuration)
        let started = model.flungAt
        DispatchQueue.main.asyncAfter(deadline: .now() + effect.arriveDuration * 1.25) { [weak self] in
            if self?.model.flungAt == started { self?.model.landing = false }
        }
        model.phase = .receiving
        model.from = from
        model.count = count
        model.progress = 0
        model.current = ""
        model.files = []
        model.thumbs = [:]
        model.message = ""
        model.pull = 0
        model.incoming = cards
        show(hideAfter: nil)
        scheduleHide(20)   // in case nothing follows; the first file cancels this
    }

    func begin(from: String, count: Int, names: [String]) {
        let flung = model.phase == .receiving && !model.incoming.isEmpty
        model.phase = .receiving
        model.from = from
        model.count = count
        model.progress = 0
        model.current = names.first ?? ""
        model.files = []
        model.thumbs = [:]
        model.message = ""
        if !flung { model.incoming = []; model.wave += 1 }
        if tucked { hideWork?.cancel(); return }
        show(hideAfter: nil)
    }

    func progress(_ fraction: Double, current: String, from: String) {
        if tucked { return }
        if model.phase != .receiving { begin(from: from, count: 0, names: [current]) }
        model.progress = fraction
        model.current = SafeName.clean(current)
    }

    func done(files: [URL], from: String) {
        if waitForLanding({ self.done(files: files, from: from) }) { return }
        tucked = false
        model.phase = .done
        model.from = from
        model.files = files
        model.count = files.count
        model.progress = 1
        model.message = folderLabel(files)
        model.incoming = []
        for url in files.prefix(4) { thumbnail(url) }
        show(hideAfter: 7)
    }

    func text(_ text: String, link: URL?, from: String) {
        if waitForLanding({ self.text(text, link: link, from: from) }) { return }
        tucked = false
        model.phase = .text
        model.from = from
        model.text = text
        model.link = link
        model.incoming = []
        model.wave += 1
        show(hideAfter: 7)
    }

    func failed(_ message: String) {
        tucked = false
        model.phase = .failed
        model.message = message
        show(hideAfter: 8)
    }

    /// Small drops finish before the cards have landed; let the show end first.
    private func waitForLanding(_ then: @escaping () -> Void) -> Bool {
        let wait = landingEnds.timeIntervalSinceNow
        guard wait > 0 else { return false }
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: then)
        return true
    }

    /// The iPhone went away. Mid-drop, say so; otherwise just tidy up.
    func lost() {
        if model.phase == .receiving {
            failed("\(model.from) disconnected before the drop finished.")
        } else if model.phase == .near {
            hide()
        }
    }

    /// Swiped up or clicked away.
    func dismiss() {
        if model.phase == .receiving { tucked = true }
        hide()
    }

    // MARK: Window

    private func show(hideAfter seconds: Double?) {
        let p = panel ?? makePanel()
        panel = p
        generation += 1
        if !p.isVisible {
            // Slide down out of the menu bar.
            place(p)
            let end = p.frame
            p.setFrame(end.offsetBy(dx: 0, dy: min(end.height, 60)), display: false)
            p.alphaValue = 0
            p.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup {
                $0.duration = 0.38
                $0.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
                p.animator().setFrame(end, display: true)
                p.animator().alphaValue = 1
            }
        } else {
            place(p, animated: true)
            if p.alphaValue < 1 { p.animator().alphaValue = 1 }
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
        generation += 1
        let mine = generation
        // Slide back up into the menu bar.
        NSAnimationContext.runAnimationGroup({
            $0.duration = 0.25
            $0.timingFunction = CAMediaTimingFunction(name: .easeIn)
            p.animator().setFrame(p.frame.offsetBy(dx: 0, dy: 40), display: true)
            p.animator().alphaValue = 0
        }) {
            guard mine == self.generation else { return }
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
        let host = PanelHost(rootView: DropCard(model: model, close: { [weak self] in self?.dismiss() }))
        host.sizingOptions = [.intrinsicContentSize]
        host.onSwipeUp = { [weak self] in self?.dismiss() }
        p.contentView = host
        model.onResize = { [weak self] in
            guard let self, let p = self.panel else { return }
            self.place(p, animated: p.isVisible)
        }
        return p
    }

    /// Centred just under the menu bar, on the screen with the menu bar.
    private func place(_ p: NSPanel, animated: Bool = false) {
        guard let screen = NSScreen.screens.first, let view = p.contentView else { return }
        let size = view.fittingSize
        let vf = screen.visibleFrame
        let frame = NSRect(x: vf.midX - size.width / 2, y: vf.maxY - size.height - 6, width: size.width, height: size.height)
        if animated {
            NSAnimationContext.runAnimationGroup { $0.duration = 0.22; p.animator().setFrame(frame, display: true) }
        } else {
            p.setFrame(frame, display: true)
        }
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

/// Hosts the card, and turns a two-finger swipe up on it into "put it away".
final class PanelHost: NSHostingView<DropCard> {
    var onSwipeUp: (() -> Void)?
    private var travel: CGFloat = 0
    private var fired = false

    override func scrollWheel(with e: NSEvent) {
        guard e.hasPreciseScrollingDeltas else { return super.scrollWheel(with: e) }
        if e.phase == .began { travel = 0; fired = false }
        // How far the fingers moved up, whichever way scrolling is set.
        travel += e.isDirectionInvertedFromDevice ? -e.scrollingDeltaY : e.scrollingDeltaY
        if !fired && travel > 30 {
            fired = true
            onSwipeUp?()
        }
        if e.phase == .ended || e.phase == .cancelled { travel = 0 }
    }
}

final class DropModel: ObservableObject {
    enum Phase { case hidden, near, receiving, done, text, failed }
    /// One of the items the iPhone just threw, as it slides in.
    struct Card: Identifiable {
        let id = UUID()
        var image: NSImage?
        var symbol: String
    }
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
    /// How far the iPhone's stack has been swiped up, 0…1.
    @Published var pull = 0.0
    @Published var incoming: [Card] = []
    /// The landing effect, and when it started; `landing` while it's playing.
    @Published var effect: DropEffect = .classic
    @Published var flungAt = Date.distantPast
    @Published var landing = false
    /// Draw one moment of the landing (seconds in), for screenshots.
    var frozen: Double?
    var onResize: (() -> Void)?
}

struct DropCard: View {
    @ObservedObject var model: DropModel
    var close: () -> Void
    @State private var slots: [CGPoint] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            switch model.phase {
            case .near:
                LandingPad(pull: model.pull)
            case .receiving:
                if !model.incoming.isEmpty {
                    IncomingRow(model: model, extra: model.count - model.incoming.count)
                }
                ProgressView(value: model.progress)
                    .tint(Color.accentDrop)
                Text(model.current.isEmpty ? "Getting ready…" : model.current)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
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
            case .hidden:
                EmptyView()
            }
        }
        .padding(14)
        .frame(width: 380, alignment: .leading)
        .background {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.regularMaterial)
                // Brightens from the top as the iPhone's swipe gets further.
                LinearGradient(colors: [Color.accentDrop.opacity(0.4 * model.pull), Color.accentDrop2.opacity(0.15 * model.pull), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .animation(.easeOut(duration: 0.15), value: model.pull)
                Wave(trigger: model.wave, holding: model.phase == .near, pull: model.phase == .near ? model.pull : 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .overlay {
            if model.landing {
                EffectCanvas(effect: model.effect, side: .arrive, start: model.flungAt, slots: slots, frozen: model.frozen)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.18)))
        .coordinateSpace(name: "card")
        .onPreferenceChange(SlotCenters.self) { slots = $0 }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture { if model.phase == .near || model.phase == .failed { close() } }
        // Drag it up with the mouse to put it away (a two-finger swipe works too, see PanelHost).
        .gesture(DragGesture(minimumDistance: 10).onEnded { if $0.translation.height < -20 { close() } })
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
        case .near: return model.pull > 0 ? "\(model.from) is dropping" : "\(model.from) is close"
        case .receiving: return model.count > 1 ? "Receiving \(model.count) items" : "Receiving"
        case .done: return model.count == 1 ? "Received 1 item" : "Received \(model.count) items"
        case .text: return model.link == nil ? "Text received" : "Link received"
        case .failed: return "Something went wrong"
        case .hidden: return ""
        }
    }

    private var subtitle: String {
        switch model.phase {
        case .near:
            if model.pull >= 1 { return "Let go on the iPhone to drop" }
            return model.pull > 0 ? "Keep swiping up…" : "Swipe up on the iPhone to drop what’s waiting"
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

/// Three empty slots while the iPhone is close. As its stack is swiped up, a card drops into each
/// slot from the top edge, one a little behind the other.
private struct LandingPad: View {
    var pull: Double

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<3) { i in
                let s = stage(i)
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .foregroundStyle(.secondary.opacity(0.6 - 0.4 * s))
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: [.accentDrop, .accentDrop2], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(Image(systemName: "arrow.down").font(.system(size: 20, weight: .bold)).foregroundStyle(.white))
                        .shadow(color: .accentDrop.opacity(0.4 * s), radius: 6, y: 2)
                        .scaleEffect(0.8 + 0.2 * s)
                        .offset(y: -44 * (1 - s))
                        .opacity(s)
                }
                .frame(width: 64, height: 64)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
        .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.75), value: pull)
    }

    private func stage(_ i: Int) -> Double { min(1, max(0, pull * 1.4 - Double(i) * 0.2)) }
}

/// The thumbnails the iPhone just threw, landing one after another with the drop's effect.
private struct IncomingRow: View {
    @ObservedObject var model: DropModel
    var extra: Int

    var body: some View {
        let cards = model.incoming
        HStack(spacing: 12) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { i, card in
                TimelineView(.animation(paused: !model.landing || model.frozen != nil)) { tl in
                    let t = (model.frozen ?? tl.date.timeIntervalSince(model.flungAt)) / model.effect.arriveDuration
                    IncomingCard(card: card)
                        .effectMotion(model.landing ? model.effect.arrive(t, index: i, of: cards.count) : EffectMotion())
                }
                .background(GeometryReader { g in
                    Color.clear.preference(key: SlotCenters.self, value: [CGPoint(x: g.frame(in: .named("card")).midX,
                                                                                  y: g.frame(in: .named("card")).midY)])
                })
            }
            if extra > 0 {
                Text("+\(extra)").font(.headline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }
}

/// Where each landing card sits in the panel, so the effect can aim at it.
private struct SlotCenters: PreferenceKey {
    static let defaultValue: [CGPoint] = []
    static func reduce(value: inout [CGPoint], nextValue: () -> [CGPoint]) { value += nextValue() }
}

private struct IncomingCard: View {
    var card: DropModel.Card

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary)
            if let image = card.image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: card.symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.accentDrop)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
    }
}

/// NameDrop's touch in the panel: a bubble of light out of the top edge and a wave rolling down, when the
/// iPhone comes close and when its swipe is far enough; the bubble stays while it's close and grows with the swipe.
struct Wave: View {
    var trigger: Int
    var holding = false
    var pull = 0.0
    @State private var start = Date.distantPast
    @State private var playing = false

    var body: some View {
        ZStack {
            if playing || holding || pull > 0 {
                TouchGlow(start: start, holding: holding, pull: pull, corner: 18)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { play() }
        .onAppear { play() }
    }

    private func play() {
        let now = Date()
        start = now
        playing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + TouchGlow.duration * 1.25) { if start == now { playing = false } }
    }
}

extension Color {
    static let accentDrop = Color(red: 0.16, green: 0.56, blue: 1.0)
    static let accentDrop2 = Color(red: 0.55, green: 0.36, blue: 0.98)
}
