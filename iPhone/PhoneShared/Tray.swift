import Foundation
import QuickLookThumbnailing
import UIKit
import UniformTypeIdentifiers

/// What's waiting to be dropped. Files are copied into a private outbox first, so the originals
/// (and the photo picker's short-lived copies) don't have to stay around while sending.
@MainActor
final class Tray: ObservableObject {
    struct Item: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var url: URL?
        var text: String?
        var size: Int64
        var thumb: UIImage?
        var symbol: String

        static func == (a: Item, b: Item) -> Bool { a.id == b.id && a.thumb === b.thumb }
    }

    @Published private(set) var items: [Item] = []
    /// Items still being read in (photos can take a moment, especially from iCloud).
    @Published var loading = 0

    var isEmpty: Bool { items.isEmpty }

    nonisolated private static let outbox: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Outbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Copies a file into the outbox. Safe to call from any thread; returns the copy.
    nonisolated static func stage(_ source: URL, name: String? = nil) throws -> URL {
        let dir = outbox.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(SafeName.clean(name ?? source.lastPathComponent))
        try FileManager.default.copyItem(at: source, to: dest)
        return dest
    }

    /// Adds a file that's already in the outbox.
    func add(staged url: URL) {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let item = Item(name: url.lastPathComponent, url: url, size: size, symbol: Tray.symbol(for: url))
        items.append(item)
        thumbnail(item)
    }

    func add(text raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let isLink = URL(string: text).map { ["http", "https"].contains($0.scheme?.lowercased() ?? "") } ?? false
        items.append(Item(name: text, text: text, size: Int64(text.utf8.count), symbol: isLink ? "link" : "text.alignleft"))
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
        if let url = item.url { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    }

    func clear() {
        for i in items { if let url = i.url { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) } }
        items = []
    }

    var summary: String {
        let files = items.filter { $0.url != nil }
        let bytes = files.reduce(0) { $0 + $1.size }
        let n = items.count
        let what = n == 1 ? "1 item" : "\(n) items"
        return bytes > 0 ? "\(what) · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))" : what
    }

    private static func symbol(for url: URL) -> String {
        guard let t = UTType(filenameExtension: url.pathExtension) else { return "doc" }
        if t.conforms(to: .image) { return "photo" }
        if t.conforms(to: .movie) { return "film" }
        if t.conforms(to: .audio) { return "waveform" }
        if t.conforms(to: .pdf) { return "doc.richtext" }
        if t.conforms(to: .archive) { return "doc.zipper" }
        return "doc"
    }

    private func thumbnail(_ item: Item) {
        guard let url = item.url else { return }
        let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 160, height: 160), scale: 3,
                                               representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { [weak self] rep, _ in
            guard let image = rep?.uiImage else { return }
            Task { @MainActor in
                guard let self, let i = self.items.firstIndex(where: { $0.id == item.id }) else { return }
                self.items[i].thumb = image
            }
        }
    }
}
