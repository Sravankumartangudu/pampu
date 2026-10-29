import SwiftUI

struct SettingsView: View {
    @ObservedObject var drop: Drop
    @ObservedObject var sender: Sender
    @ObservedObject var proximity: Proximity
    @Environment(\.dismiss) private var dismiss

    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("compatiblePhotos") private var compatiblePhotos = false
    @State private var name = Identity.name
    @State private var closeness = DropSettings.closeness
    @State private var closeAction = DropSettings.closeAction
    @State private var effect = DropSettings.effect

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("iPhone name", text: $name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit { Identity.name = name }
                } header: {
                    Text("This iPhone")
                } footer: {
                    Text("Shown on your Mac. Takes effect the next time Pampu opens.")
                }

                Section {
                    Picker("When brought close", selection: $closeAction) {
                        ForEach(CloseAction.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: closeAction) { _, a in DropSettings.closeAction = a; drop.closeAction = a }
                    Picker("How close", selection: $closeness) {
                        ForEach(Closeness.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: closeness) { _, c in DropSettings.closeness = c; proximity.threshold = c.dBm }
                    LabeledContent("Signal now", value: proximity.current.map { "\(Int($0)) dBm" } ?? "—")
                    LabeledContent("Counts as close at", value: "\(Int(closeness.dBm)) dBm or stronger")
                } header: {
                    Text("Bringing it close")
                } footer: {
                    Text(proximity.bluetooth == "on"
                         ? (closeAction == .swipe
                            ? "Hold the top of your iPhone near your Mac’s keyboard or screen; both glow, then swipe the stack up. If the glow comes too early, pick Touching; if it never comes, pick Nearby."
                            : "Hold the top of your iPhone near your Mac’s keyboard or screen and it drops by itself. If it drops too early, pick Touching; if it never drops, pick Nearby.")
                         : "Bluetooth is \(proximity.bluetooth == "denied" ? "not allowed for Pampu — turn it on in Settings › Pampu" : "off"). Swiping up and Send Now still work.")
                }

                Section {
                    NavigationLink {
                        EffectPicker(choice: $effect)
                    } label: {
                        LabeledContent("Drop effect") {
                            Text(DropEffect(rawValue: effect).map { "\($0.emoji) \($0.title)" } ?? "🎲 Random")
                        }
                    }
                    .onChange(of: effect) { _, e in DropSettings.effect = e }
                } header: {
                    Text("Effect")
                } footer: {
                    Text("How the stack leaves your iPhone — your Mac plays the matching landing.")
                }

                Section {
                    Toggle("Most compatible photos (JPEG)", isOn: $compatiblePhotos)
                } header: {
                    Text("Photos")
                } footer: {
                    Text("Off keeps photos as they are (HEIC, full quality).")
                }

                Section("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    let paired = sender.macs.filter(\.paired)
                    if paired.isEmpty {
                        Text("No paired Mac nearby").foregroundStyle(.secondary)
                    }
                    ForEach(paired) { mac in
                        HStack {
                            Label(mac.name, systemImage: "laptopcomputer")
                            Spacer()
                            Button("Forget", role: .destructive) { sender.forget(mac) }
                        }
                    }
                } header: {
                    Text("Paired Macs")
                } footer: {
                    Text("To unpair from the Mac side, use 🪂 › Paired iPhones.")
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    Link("Pampu on GitHub", destination: URL(string: "https://github.com/Sravankumartangudu/pampu")!)
                } footer: {
                    Text("“Pampu” means “send” in Telugu. Files go straight from your iPhone to your Mac over an encrypted peer-to-peer link — no cloud, no account.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { Identity.name = name; dismiss() }
                }
            }
        }
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
    }
}

// MARK: - Drop effect

/// Every effect, with a live preview of the one picked at the top.
private struct EffectPicker: View {
    @Binding var choice: String

    var body: some View {
        List {
            Section {
                EffectPreview(effects: DropEffect(rawValue: choice).map { [$0] } ?? DropEffect.allCases)
                    .id(choice)
                    .listRowInsets(EdgeInsets())
            }
            Section {
                row(DropEffect.randomChoice, emoji: "🎲", title: "Random", blurb: "A different one every drop")
                ForEach(DropEffect.allCases) { e in row(e.rawValue, emoji: e.emoji, title: e.title, blurb: e.blurb) }
            } footer: {
                Text("Your Mac plays the matching landing, whichever you pick.")
            }
        }
        .navigationTitle("Drop Effect")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ id: String, emoji: String, title: String, blurb: String) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            choice = id
        } label: {
            HStack(spacing: 14) {
                Text(emoji).font(.system(size: 30)).frame(width: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(blurb).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if choice == id {
                    Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(Theme.gradient)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(choice == id ? .isSelected : [])
    }
}

/// A pretend stack playing the effect on a loop (or each in turn, for Random).
private struct EffectPreview: View {
    var effects: [DropEffect]
    @State private var start = Date()
    private static let cycle = 3.0   // 0.4 s to appear, the effect, then a pause

    var body: some View {
        GeometryReader { g in
            let origin = CGPoint(x: g.size.width / 2, y: g.size.height - 95)
            TimelineView(.animation) { tl in
                let total = tl.date.timeIntervalSince(start)
                let effect = effects[Int(total / Self.cycle) % effects.count]
                let local = total.truncatingRemainder(dividingBy: Self.cycle)
                let shown = local - 0.4
                ZStack {
                    LinearGradient(colors: [Color(red: 0.05, green: 0.08, blue: 0.2), Color(red: 0.12, green: 0.07, blue: 0.28)],
                                   startPoint: .top, endPoint: .bottom)
                    card
                        .scaleEffect(local < 0.4 ? 0.6 + 0.4 * min(1, local / 0.3) : 1)
                        .opacity(local < 0.4 ? min(1, local / 0.2) : 1)
                        .effectMotion(shown > 0 ? effect.send(shown / effect.sendDuration) : EffectMotion())
                        .position(origin)
                    EffectCanvas(effect: effect, side: .send, start: tl.date, origin: origin, frozen: max(shown, -1))
                    VStack {
                        Spacer()
                        Text("\(effect.emoji)  \(effect.title)")
                            .font(.headline).foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Capsule().fill(.white.opacity(0.14)))
                            .padding(.bottom, 14)
                    }
                }
            }
        }
        .frame(height: 440)
        .clipped()
        .onAppear { start = Date() }
    }

    private var card: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.gradient)
            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 40, weight: .semibold)).foregroundStyle(.white)
        }
        .frame(width: 100, height: 100)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.9), lineWidth: 3))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
    }
}
