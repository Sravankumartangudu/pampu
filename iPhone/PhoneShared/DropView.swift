import Combine
import SwiftUI
import UIKit

/// Ties the sender, the proximity reader and the tray together: when the phone is brought close to a
/// paired Mac with something waiting, it buzzes, the glow rolls down from the top and the items drop.
@MainActor
final class Drop: ObservableObject {
    let sender = Sender()
    let proximity = Proximity()
    let tray = Tray()

    @Published private(set) var wave = 0
    var autoSend = DropSettings.autoSend
    /// Called after a successful drop (the Share extension closes itself).
    var onSent: (() -> Void)?

    private var bag = Set<AnyCancellable>()
    private let tap = UIImpactFeedbackGenerator(style: .heavy)
    private let note = UINotificationFeedbackGenerator()

    init() {
        proximity.$isClose.removeDuplicates().dropFirst().sink { [weak self] close in
            self?.closeChanged(close)
        }.store(in: &bag)
        sender.$targetId.sink { [weak self] id in
            self?.proximity.target = id.map { String($0.prefix(8)) }
        }.store(in: &bag)
    }

    func start() {
        proximity.threshold = DropSettings.closeness.dBm
        autoSend = DropSettings.autoSend
        sender.start()
        proximity.start()
        tap.prepare()
    }

    func stop() {
        sender.stop()
        proximity.stop()
    }

    var canSend: Bool { sender.link == .ready && !tray.isEmpty && !sender.isSending && tray.loading == 0 }

    func dropNow() {
        guard canSend else { return }
        let items = tray.items
        wave += 1
        tap.impactOccurred()
        Task {
            if await sender.send(items) {
                note.notificationOccurred(.success)
                tray.clear()
                onSent?()
                try? await Task.sleep(for: .seconds(2.5))
                sender.clearJob()
            } else {
                note.notificationOccurred(.error)
            }
        }
    }

    private func closeChanged(_ close: Bool) {
        sender.near(close)
        guard close else { return }
        if autoSend && canSend {
            dropNow()
        } else {
            wave += 1
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

// MARK: - Screen

struct DropView<Accessory: View>: View {
    @ObservedObject var drop: Drop
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        DropScreen(drop: drop, sender: drop.sender, proximity: drop.proximity, tray: drop.tray, accessory: accessory)
    }
}

private struct DropScreen<Accessory: View>: View {
    @ObservedObject var drop: Drop
    @ObservedObject var sender: Sender
    @ObservedObject var proximity: Proximity
    @ObservedObject var tray: Tray
    var accessory: () -> Accessory

    var body: some View {
        ZStack(alignment: .top) {
            Backdrop()
            VStack(spacing: 16) {
                MacCard(sender: sender, proximity: proximity)
                Spacer(minLength: 8)
                DropZone(sender: sender, tray: tray, ready: sender.link == .ready, close: proximity.isClose)
                hint
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                    .padding(.horizontal)
                if !tray.isEmpty { TrayStrip(tray: tray, locked: sender.isSending) }
                Spacer(minLength: 8)
                accessory()
                primaryButton
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            TopWave(trigger: drop.wave)
                .ignoresSafeArea()
        }
        .animation(.spring(duration: 0.35), value: tray.items.count)
        .animation(.easeInOut(duration: 0.25), value: sender.link)
        .alert(sender.notice ?? "", isPresented: Binding(get: { sender.notice != nil }, set: { if !$0 { sender.notice = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    @ViewBuilder private var hint: some View {
        switch sender.job {
        case .sending(let done, let total):
            Text("Dropping \(min(done + 1, total)) of \(total)…")
        case .sent(let n):
            Text("Dropped \(n == 1 ? "1 item" : "\(n) items") on \(sender.target?.name ?? "your Mac")")
                .foregroundStyle(.primary)
        case .failed(let msg):
            Text(msg).foregroundStyle(.red)
        case .idle:
            switch sender.link {
            case .pairing(let code):
                VStack(spacing: 6) {
                    Text(code).font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.primary)
                    Text("Click Allow on your Mac if it shows the same code.")
                }
            case .needsPair:
                Text("Pair once, and this iPhone can drop files on \(sender.target?.name ?? "the Mac") any time.")
            case .denied(let msg):
                Text(msg)
            case .ready:
                if tray.loading > 0 { Text("Getting your items ready…") }
                else if tray.isEmpty { Text("Pick photos, files or a link to drop.") }
                else if drop.autoSend && proximity.bluetooth == "on" { Text("Bring the top of your iPhone close to your Mac.") }
                else { Text("Tap Send to drop \(tray.summary).") }
            case .off, .searching, .connecting:
                Text("Open Pampu on your Mac. Keep Wi-Fi and Bluetooth on — you don’t need the same network.")
            }
        }
    }

    @ViewBuilder private var primaryButton: some View {
        if sender.link == .needsPair {
            Button { sender.pair() } label: {
                Label("Pair with \(sender.target?.name ?? "Mac")", systemImage: "link").frame(maxWidth: .infinity)
            }
            .buttonStyle(BigButton())
        } else if sender.link == .ready && !tray.isEmpty {
            Button { drop.dropNow() } label: {
                Label(sender.isSending ? "Dropping…" : "Send Now", systemImage: "paperplane.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(BigButton())
            .disabled(!drop.canSend)
        }
    }
}

// MARK: - Pieces

private struct MacCard: View {
    @ObservedObject var sender: Sender
    @ObservedObject var proximity: Proximity

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Theme.gradient)
                .frame(width: 44, height: 44)
                .background(Circle().fill(.thinMaterial))
            VStack(alignment: .leading, spacing: 2) {
                Text(sender.target?.name ?? "Looking for your Mac…").font(.headline).lineLimit(1)
                Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if sender.link == .ready && proximity.bluetooth == "on" {
                SignalBars(strength: proximity.strength, close: proximity.isClose)
            } else if sender.link == .connecting || sender.link == .searching {
                ProgressView()
            }
            if sender.macs.count > 1 {
                Menu {
                    ForEach(sender.macs) { mac in
                        Button { sender.choose(mac) } label: {
                            Label(mac.name, systemImage: mac.id == sender.targetId ? "checkmark" : (mac.paired ? "link" : "laptopcomputer"))
                        }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down").font(.footnote.weight(.semibold))
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.regularMaterial))
    }

    private var status: String {
        switch sender.link {
        case .off, .searching: return sender.macs.isEmpty ? "Searching nearby" : "Found — tap the arrows to pick"
        case .connecting: return "Connecting…"
        case .needsPair: return "Not paired yet"
        case .pairing: return "Waiting for you to click Allow"
        case .denied: return "Not allowed"
        case .ready:
            switch proximity.bluetooth {
            case "off": return "Connected · Bluetooth off, tap Send"
            case "denied": return "Connected · allow Bluetooth for hold-to-drop"
            default: return proximity.isClose ? "Close enough to drop" : "Connected"
            }
        }
    }
}

private struct SignalBars: View {
    var strength: Double
    var close: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<5) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Double(i) / 5 < strength ? AnyShapeStyle(close ? AnyShapeStyle(Color.green) : AnyShapeStyle(Theme.gradient))
                                                  : AnyShapeStyle(Color.secondary.opacity(0.25)))
                    .frame(width: 4, height: 6 + CGFloat(i) * 4)
            }
        }
        .animation(.easeOut(duration: 0.2), value: strength)
        .accessibilityLabel("Signal \(Int(strength * 100)) percent")
    }
}

private struct DropZone: View {
    @ObservedObject var sender: Sender
    @ObservedObject var tray: Tray
    var ready: Bool
    var close: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            if ready && !tray.isEmpty {
                ForEach(0..<3) { i in
                    Circle()
                        .stroke(Theme.gradient, lineWidth: 2)
                        .scaleEffect(pulse ? 1.45 : 0.85)
                        .opacity(pulse ? 0 : 0.55)
                        .animation(.easeOut(duration: 2.2).repeatForever(autoreverses: false).delay(Double(i) * 0.7), value: pulse)
                }
            }
            Circle()
                .fill(.regularMaterial)
                .overlay(Circle().fill(Theme.gradient.opacity(close ? 0.35 : 0.12)))
                .shadow(color: Theme.blue.opacity(close ? 0.6 : 0.2), radius: close ? 30 : 14)

            if case .sending = sender.job {
                Circle()
                    .trim(from: 0, to: sender.progress)
                    .stroke(Theme.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(4)
                    .animation(.linear(duration: 0.15), value: sender.progress)
            }
            content
        }
        .frame(width: 230, height: 230)
        .scaleEffect(close ? 1.06 : 1)
        .animation(.spring(duration: 0.4, bounce: 0.4), value: close)
        .onAppear { pulse = true }
    }

    @ViewBuilder private var content: some View {
        if case .sent = sender.job {
            Image(systemName: "checkmark")
                .font(.system(size: 70, weight: .bold))
                .foregroundStyle(Theme.gradient)
                .transition(.scale.combined(with: .opacity))
        } else if tray.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: tray.loading > 0 ? "hourglass" : "arrow.down.to.line.compact")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(Theme.gradient)
                Text(Brand.name).font(.title3.weight(.bold))
            }
        } else {
            ZStack {
                ForEach(Array(tray.items.prefix(3).enumerated().reversed()), id: \.element.id) { i, item in
                    Thumb(item: item, size: 110)
                        .rotationEffect(.degrees(Double(i) * 8 - 8))
                        .offset(x: CGFloat(i) * 10 - 10, y: CGFloat(i) * -6)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if tray.items.count > 1 {
                    Text("\(tray.items.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Theme.gradient))
                        .offset(x: 18, y: 10)
                }
            }
        }
    }
}

struct Thumb: View {
    var item: Tray.Item
    var size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.16, style: .continuous).fill(.background)
            if let t = item.thumb {
                Image(uiImage: t).resizable().scaledToFill()
            } else if let text = item.text {
                VStack(spacing: 4) {
                    Image(systemName: item.symbol).font(.system(size: size * 0.22, weight: .semibold)).foregroundStyle(Theme.gradient)
                    Text(text).font(.system(size: max(9, size * 0.09))).lineLimit(3).multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding(size * 0.08)
            } else {
                Image(systemName: item.symbol).font(.system(size: size * 0.32)).foregroundStyle(Theme.gradient)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.16, style: .continuous).strokeBorder(.white.opacity(0.9), lineWidth: size > 60 ? 3 : 1.5))
        .shadow(color: .black.opacity(0.18), radius: size > 60 ? 8 : 3, y: 3)
    }
}

private struct TrayStrip: View {
    @ObservedObject var tray: Tray
    var locked: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(tray.summary).font(.footnote.weight(.semibold))
                Spacer()
                Button("Clear", role: .destructive) { tray.clear() }
                    .font(.footnote)
                    .disabled(locked)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tray.items) { item in
                        Thumb(item: item, size: 52)
                            .overlay(alignment: .topTrailing) {
                                if !locked {
                                    Button { tray.remove(item) } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.55))
                                    }
                                    .offset(x: 5, y: -5)
                                    .accessibilityLabel("Remove \(item.name)")
                                }
                            }
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 2)
            }
        }
    }
}

/// The NameDrop-style glow that rolls down from the top edge.
private struct TopWave: View {
    var trigger: Int
    @State private var t: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            Ellipse()
                .fill(RadialGradient(colors: [.white.opacity(0.9), Theme.blue.opacity(0.65), Theme.violet.opacity(0.3), .clear],
                                     center: .center, startRadius: 0, endRadius: w * 0.7))
                .frame(width: w * (0.4 + t * 1.6), height: 120 + t * geo.size.height * 0.9)
                .position(x: w / 2, y: -40 + t * geo.size.height * 0.25)
                .opacity(Double(1 - t))
                .blur(radius: 18)
                .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) {
            t = 0
            withAnimation(.easeOut(duration: 1.2)) { t = 1 }
        }
    }
}

private struct Backdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        LinearGradient(colors: scheme == .dark
                       ? [Color(red: 0.05, green: 0.08, blue: 0.2), Color(red: 0.1, green: 0.06, blue: 0.24)]
                       : [Color(red: 0.9, green: 0.95, blue: 1.0), Color(red: 0.94, green: 0.91, blue: 1.0)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

struct BigButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.gradient))
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

enum Theme {
    static let blue = Color(red: 0.16, green: 0.56, blue: 1.0)
    static let violet = Color(red: 0.42, green: 0.3, blue: 0.9)
    static let gradient = LinearGradient(colors: [blue, violet], startPoint: .topLeading, endPoint: .bottomTrailing)
}
