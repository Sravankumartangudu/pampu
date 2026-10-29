import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let prefs = Prefs.shared
    private let receiver = Receiver.shared
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        prefs.applyAppearance()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🪂"
        statusItem.button?.toolTip = Brand.name
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        NexusBeacon.start(name: Brand.name) { [weak self] in
            guard let self else { return ("ok", "") }
            return self.health()
        }
        NexusBeacon.attach(statusItem)

        receiver.onChange = { [weak self] in self?.refresh() }
        ProximityBeacon.shared.onChange = { [weak self] in self?.refresh() }
        if prefs.receiving { receiver.start() }
        refresh()

        if CommandLine.arguments.contains("--demo") { demo() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem.button?.performClick(nil)
        return false
    }

    private func refresh() {
        statusItem.button?.appearsDisabled = !prefs.receiving
        NexusBeacon.beat()
    }

    /// One line for the menu header and the Nexus heartbeat.
    private func health() -> (String, String) {
        if !prefs.receiving { return ("warn", "receiving is off") }
        if let err = receiver.advertiseError { return ("error", "can’t listen: \(err)") }
        let connected = receiver.connectedNames
        let paired = Devices.shared.all.count
        var detail = connected.isEmpty
            ? (paired == 0 ? "ready · no iPhone paired yet" : "ready · \(paired) iPhone\(paired == 1 ? "" : "s") paired")
            : "connected · \(connected.joined(separator: ", "))"
        switch ProximityBeacon.shared.state {
        case "off": detail += " · Bluetooth off (tap Send on the iPhone)"
        case "denied": detail += " · Bluetooth not allowed"
        default: break
        }
        return ("ok", detail)
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let head = NSMenuItem(title: "\(Brand.name) — \(health().1)", action: nil, keyEquivalent: "")
        head.isEnabled = false
        menu.addItem(head)
        menu.addItem(.separator())

        menu.addItem(toggle("Receiving", prefs.receiving, #selector(toggleReceiving)))

        let recent = NSMenuItem(title: "Recent Drops", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        if receiver.recent.isEmpty {
            let none = NSMenuItem(title: "Nothing yet", action: nil, keyEquivalent: "")
            none.isEnabled = false
            sub.addItem(none)
        } else {
            for url in receiver.recent {
                let i = NSMenuItem(title: url.lastPathComponent, action: #selector(revealRecent(_:)), keyEquivalent: "")
                i.target = self
                i.representedObject = url
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 16, height: 16)
                i.image = icon
                sub.addItem(i)
            }
        }
        recent.submenu = sub
        menu.addItem(recent)
        menu.addItem(item("Open Drop Folder", #selector(openFolder), key: "o"))
        menu.addItem(.separator())

        menu.addItem(item("Change Drop Folder…", #selector(chooseFolder)))
        menu.addItem(toggle("Sort Into Folders by Type", prefs.sortByType, #selector(toggleSort)))
        menu.addItem(toggle("Open Links Automatically", prefs.openLinks, #selector(toggleLinks)))
        menu.addItem(toggle("Play Sounds", prefs.playSound, #selector(toggleSound)))
        menu.addItem(.separator())

        let paired = NSMenuItem(title: "Paired iPhones", action: nil, keyEquivalent: "")
        let ps = NSMenu()
        let devices = Devices.shared.all
        if devices.isEmpty {
            let none = NSMenuItem(title: "None yet — open \(Brand.name) on your iPhone and tap Pair", action: nil, keyEquivalent: "")
            none.isEnabled = false
            ps.addItem(none)
        } else {
            for d in devices {
                let i = NSMenuItem(title: "Forget “\(d.name)”", action: #selector(forget(_:)), keyEquivalent: "")
                i.target = self
                i.representedObject = d.id
                if let seen = d.lastSeen {
                    i.toolTip = "Last seen " + RelativeDateTimeFormatter().localizedString(for: seen, relativeTo: Date())
                }
                ps.addItem(i)
            }
            ps.addItem(.separator())
            ps.addItem(item("Forget All", #selector(forgetAll)))
        }
        paired.submenu = ps
        menu.addItem(paired)
        menu.addItem(item("How to Send from iPhone…", #selector(howTo)))

        let look = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        let ls = NSMenu()
        for (id, title) in [("system", "System"), ("light", "Light"), ("dark", "Dark")] {
            let i = NSMenuItem(title: title, action: #selector(pickAppearance(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = id
            i.state = prefs.appearance == id ? .on : .off
            ls.addItem(i)
        }
        look.submenu = ls
        menu.addItem(look)
        menu.addItem(toggle("Launch at Login", SMAppService.mainApp.status == .enabled, #selector(toggleLogin)))
        menu.addItem(.separator())
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        menu.addItem(item("About \(Brand.name) \(version)", #selector(about)))
        menu.addItem(item("Quit \(Brand.name)", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    private func toggle(_ title: String, _ on: Bool, _ action: Selector) -> NSMenuItem {
        let i = item(title, action)
        i.state = on ? .on : .off
        return i
    }

    // MARK: Actions

    @objc private func toggleReceiving() {
        prefs.receiving.toggle()
        prefs.receiving ? receiver.start() : receiver.stop()
        refresh()
    }

    @objc private func revealRecent(_ i: NSMenuItem) {
        guard let url = i.representedObject as? URL else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSSound.beep()
        }
    }

    @objc private func openFolder() {
        try? FileManager.default.createDirectory(at: prefs.folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(prefs.folder)
    }

    @objc private func chooseFolder() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        panel.message = "Where should files from your iPhone land?"
        panel.directoryURL = prefs.folder.deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url { prefs.folder = url }
    }

    @objc private func toggleSort() { prefs.sortByType.toggle() }
    @objc private func toggleLinks() { prefs.openLinks.toggle() }
    @objc private func toggleSound() { prefs.playSound.toggle() }

    @objc private func forget(_ i: NSMenuItem) {
        guard let id = i.representedObject as? String else { return }
        Devices.shared.forget(id)
        receiver.disconnect(deviceId: id)
        refresh()
    }

    @objc private func forgetAll() {
        Devices.shared.forgetAll()
        receiver.disconnect(deviceId: nil)
        refresh()
    }

    @objc private func pickAppearance(_ i: NSMenuItem) { prefs.appearance = i.representedObject as? String ?? "system" }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            NSAlert(error: error).runModal()
        }
    }

    @objc private func howTo() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Send from your iPhone"
        a.informativeText = """
        1. Open \(Brand.name) on your iPhone. The first time, tap Pair and click Allow here (check the code matches).
        2. Pick photos, files or paste a link — or use Share › \(Brand.name) in any app.
        3. Bring the top of your iPhone close to this Mac. It buzzes, the glow rolls out, and the files drop into \(prefs.folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).

        No Bluetooth? Tap Send on the iPhone instead. Both devices just need Wi-Fi and Bluetooth switched on — they don’t have to be on the same network.
        """
        a.runModal()
    }

    @objc private func about() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "Hold your iPhone close to drop files onto this Mac.\n“Pampu” means “send” in Telugu."),
        ])
    }

    @objc private func quit() { NSApp.terminate(nil) }

    /// `--demo`: plays the panel's states so they can be checked without a phone.
    private func demo() {
        let p = DropPanel.shared
        p.near(from: "Demo iPhone")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { p.begin(from: "Demo iPhone", count: 3, names: ["IMG_0042.HEIC"]) }
        for (n, f) in [(2.5, 0.2), (3.0, 0.55), (3.5, 0.9)] {
            DispatchQueue.main.asyncAfter(deadline: .now() + n) { p.progress(f, current: "IMG_0042.HEIC", from: "Demo iPhone") }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) {
            let samples = ["/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/iPhone.icns",
                           "/System/Applications/Photos.app", "/System/Applications/Preview.app"].map { URL(fileURLWithPath: $0) }
            p.done(files: samples, from: "Demo iPhone")
        }
    }
}
