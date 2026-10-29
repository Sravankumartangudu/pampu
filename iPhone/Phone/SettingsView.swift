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
    @State private var autoSend = DropSettings.autoSend

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
                    Toggle("Send when brought close", isOn: $autoSend)
                        .onChange(of: autoSend) { _, on in DropSettings.autoSend = on; drop.autoSend = on }
                    Picker("How close", selection: $closeness) {
                        ForEach(Closeness.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: closeness) { _, c in DropSettings.closeness = c; proximity.threshold = c.dBm }
                    LabeledContent("Signal now", value: proximity.current.map { "\(Int($0)) dBm" } ?? "—")
                    LabeledContent("Drops at", value: "\(Int(closeness.dBm)) dBm or stronger")
                } header: {
                    Text("Bring close to drop")
                } footer: {
                    Text(proximity.bluetooth == "on"
                         ? "Hold the top of your iPhone near your Mac’s keyboard or screen. If it drops too early, pick Touching; if it never drops, pick Nearby."
                         : "Bluetooth is \(proximity.bluetooth == "denied" ? "not allowed for Pampu — turn it on in Settings › Pampu" : "off"). The Send button still works.")
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
