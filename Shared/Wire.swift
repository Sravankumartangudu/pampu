// Wire — the small protocol the iPhone and the Mac speak over MultipeerConnectivity.
// This one file is compiled into the Mac app (build.sh) and both iPhone targets (Xcode), so keep it
// Foundation + CryptoKit only.
//
// Conversation, once the encrypted session is up:
//   Mac → phone   hello  {id: macId, name, nonce}
//   phone → Mac   auth   {id: deviceId, name, proof: HMAC(secret, deviceId|nonce)}      (already paired)
//              or pair   {id: deviceId, name, code}                                     (first time)
//   Mac → phone   ok | paired {secret} | denied
//   phone → Mac   near · batch {count, bytes, names} · text {text} · then one resource per file
//   phone → Mac   pull {f: 0…1} while the stack is being swiped up (unreliable, ~20 a second;
//                 the last 0 or 1 reliable) · fling {count, kinds, thumbs, effect} the moment it's let go
//   Mac → phone   saved {name} after each file
import Foundation
import CryptoKit

enum Brand {
    static let name = "Pampu"
    /// Bonjour service type for MultipeerConnectivity: 1–15 chars of a–z, 0–9 and hyphens.
    /// Info.plists list it as _pampu-drop._tcp / _udp.
    static let serviceType = "pampu-drop"
    /// The Mac advertises this Bluetooth service so the iPhone can tell how close it is.
    static let proximityService = "0E4A2403-035C-4FF1-B7AA-1A0642AEC04E"
    static let protocolVersion = 1
}

struct Wire: Codable, Equatable {
    var t: String
    var id: String? = nil
    var name: String? = nil
    var nonce: String? = nil
    var code: String? = nil
    var proof: String? = nil
    var secret: String? = nil
    var text: String? = nil
    var count: Int? = nil
    var bytes: Int64? = nil
    var names: [String]? = nil
    /// How far the swipe has got, 0…1.
    var f: Double? = nil
    /// SF Symbol per item, and a small base64 JPEG ("" if none), for the first few items of a fling.
    var kinds: [String]? = nil
    var thumbs: [String]? = nil
    /// Which DropEffect the iPhone is playing, so the Mac plays the other half.
    var effect: String? = nil
    var v: Int? = Brand.protocolVersion

    var data: Data { (try? JSONEncoder().encode(self)) ?? Data() }
    static func decode(_ d: Data) -> Wire? { try? JSONDecoder().decode(Wire.self, from: d) }
}

enum Proof {
    static func random(_ count: Int = 32) -> Data {
        var g = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &g) })
    }

    static func make(secret: Data, device: String, nonce: String) -> String {
        let code = HMAC<SHA256>.authenticationCode(for: message(device, nonce), using: SymmetricKey(data: secret))
        return Data(code).base64EncodedString()
    }

    /// Constant-time check of a proof the phone sent back.
    static func check(_ proof: String, secret: Data, device: String, nonce: String) -> Bool {
        guard let mac = Data(base64Encoded: proof) else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: message(device, nonce),
                                                       using: SymmetricKey(data: secret))
    }

    /// Four digits shown on both screens while pairing, so you know you're allowing the right iPhone.
    static func pairCode() -> String { String(format: "%04d", Int.random(in: 0...9999)) }

    private static func message(_ device: String, _ nonce: String) -> Data { Data("\(device)|\(nonce)".utf8) }
}

/// Turns whatever name the sender gave a file into a safe, plain file name.
enum SafeName {
    static func clean(_ raw: String) -> String {
        var s = (raw as NSString).lastPathComponent
        s = s.replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "/", with: "-")
        s = s.filter { !$0.isNewline && $0 != "\0" }
        while s.hasPrefix(".") { s.removeFirst() }
        s = s.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { s = "File" }
        if s.count > 200 {
            let ext = (s as NSString).pathExtension
            let base = String((s as NSString).deletingPathExtension.prefix(180))
            s = ext.isEmpty ? base : "\(base).\(ext)"
        }
        return s
    }
}
