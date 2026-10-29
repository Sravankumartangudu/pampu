import Foundation
import Security
import UIKit

/// Small strings both the app and the Share extension need: this iPhone's id and name, each Mac's
/// pairing secret, and the drop settings. They live in a keychain group the two targets share
/// (free Apple ID profiles allow any `TEAMID.*` group, so no paid capability is needed).
enum Keychain {
    private static let service = "com.stangudu.pampuphone"
    private static let group = Bundle.main.object(forInfoDictionaryKey: "PampuKeychainGroup") as? String

    private static func base(_ key: String) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: key]
        if let group, !group.hasPrefix("$(") { q[kSecAttrAccessGroup as String] = group }
        return q
    }

    static func get(_ key: String) -> String? {
        var q = base(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ key: String, _ value: String?) {
        let q = base(key)
        SecItemDelete(q as CFDictionary)
        guard let value else { return }
        var add = q
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}

enum Identity {
    static let deviceId: String = {
        if let id = Keychain.get("deviceId") { return id }
        let id = UUID().uuidString
        Keychain.set("deviceId", id)
        return id
    }()

    /// iOS only reports "iPhone" to apps, so you can give it a nicer name in Settings.
    static var name: String {
        get { Keychain.get("deviceName").flatMap { $0.isEmpty ? nil : $0 } ?? UIDevice.current.name }
        set { Keychain.set("deviceName", newValue.trimmingCharacters(in: .whitespaces)) }
    }

    static func secret(for macId: String) -> Data? { Keychain.get("secret.\(macId)").flatMap { Data(base64Encoded: $0) } }
    static func setSecret(_ secret: Data?, for macId: String) { Keychain.set("secret.\(macId)", secret?.base64EncodedString()) }

    /// The Mac you last sent to; it's picked first when more than one is around.
    static var lastMac: String? {
        get { Keychain.get("lastMac") }
        set { Keychain.set("lastMac", newValue) }
    }
}

/// How close counts as "close". Bluetooth signal strength in dBm: higher is closer.
enum Closeness: String, CaseIterable, Identifiable {
    case touching, close, nearby
    var id: String { rawValue }
    var label: String {
        switch self {
        case .touching: return "Touching"
        case .close: return "Close"
        case .nearby: return "Nearby"
        }
    }
    var dBm: Double {
        switch self {
        case .touching: return -40
        case .close: return -50
        case .nearby: return -60
        }
    }
}

/// What bringing the iPhone close does: wait for a swipe up (like NameDrop), or drop straight away.
enum CloseAction: String, CaseIterable, Identifiable {
    case swipe, drop
    var id: String { rawValue }
    var label: String { self == .swipe ? "Swipe Up" : "Drop Right Away" }
}

enum DropSettings {
    static var closeness: Closeness {
        get { Keychain.get("closeness").flatMap(Closeness.init) ?? .close }
        set { Keychain.set("closeness", newValue.rawValue) }
    }
    static var closeAction: CloseAction {
        get { Keychain.get("closeAction").flatMap(CloseAction.init) ?? .swipe }
        set { Keychain.set("closeAction", newValue.rawValue) }
    }
}
