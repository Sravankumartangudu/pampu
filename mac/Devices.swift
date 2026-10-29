import Foundation

/// iPhones you've allowed. Each one holds a random secret the phone proves it knows every time it
/// connects, so a nearby stranger running Pampu can't pretend to be your phone.
struct Device: Codable, Equatable {
    var id: String
    var name: String
    var secret: String
    var added: Date
    var lastSeen: Date?
}

final class Devices {
    static let shared = Devices()

    private let lock = NSLock()
    private var list: [Device] = []
    private let file: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Brand.name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return dir.appendingPathComponent("devices.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([Device].self, from: data) {
            list = saved
        }
    }

    var all: [Device] { lock.withLock { list } }

    func find(_ id: String) -> Device? { lock.withLock { list.first { $0.id == id } } }

    /// Adds (or re-pairs) a phone and returns the new secret to hand it.
    func add(id: String, name: String) -> Data {
        let secret = Proof.random()
        lock.withLock {
            list.removeAll { $0.id == id }
            list.append(Device(id: id, name: name, secret: secret.base64EncodedString(), added: Date(), lastSeen: Date()))
            save()
        }
        return secret
    }

    func touch(_ id: String, name: String) {
        lock.withLock {
            guard let i = list.firstIndex(where: { $0.id == id }) else { return }
            list[i].lastSeen = Date()
            list[i].name = name
            save()
        }
    }

    func forget(_ id: String) { lock.withLock { list.removeAll { $0.id == id }; save() } }
    func forgetAll() { lock.withLock { list.removeAll(); save() } }

    /// Call with the lock held.
    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(list) else { return }
        try? data.write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
