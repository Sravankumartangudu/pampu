import AppKit

/// Everything the Mac remembers between launches. UserDefaults is thread-safe, and the receiver
/// reads these from MultipeerConnectivity's own queue.
final class Prefs {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    /// This Mac's id, sent to phones so they know which Mac they paired with.
    let macId: String

    private init() {
        if let id = d.string(forKey: "macId") {
            macId = id
        } else {
            macId = UUID().uuidString
            d.set(macId, forKey: "macId")
        }
    }

    var receiving: Bool {
        get { d.object(forKey: "receiving") as? Bool ?? true }
        set { d.set(newValue, forKey: "receiving") }
    }

    static let defaultFolder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(Brand.name, isDirectory: true)

    var folder: URL {
        get { d.string(forKey: "folder").map { URL(fileURLWithPath: $0, isDirectory: true) } ?? Prefs.defaultFolder }
        set { d.set(newValue.path, forKey: "folder") }
    }

    /// Smart filing: Photos, Videos, Screenshots, Documents, Audio, Archives, Other.
    var sortByType: Bool {
        get { d.object(forKey: "sortByType") as? Bool ?? true }
        set { d.set(newValue, forKey: "sortByType") }
    }

    var playSound: Bool {
        get { d.object(forKey: "playSound") as? Bool ?? true }
        set { d.set(newValue, forKey: "playSound") }
    }

    /// Links that arrive are always copied to the clipboard; this also opens them in the browser.
    var openLinks: Bool {
        get { d.bool(forKey: "openLinks") }
        set { d.set(newValue, forKey: "openLinks") }
    }

    /// How cards land: "match" (whatever the iPhone threw), "random", or a DropEffect name.
    var landing: String {
        get { d.string(forKey: "landing") ?? "match" }
        set { d.set(newValue, forKey: "landing") }
    }

    /// system | light | dark. Missing means system.
    var appearance: String {
        get { d.string(forKey: "appearance") ?? "system" }
        set { d.set(newValue, forKey: "appearance"); applyAppearance() }
    }

    func applyAppearance() {
        switch appearance {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }
}
