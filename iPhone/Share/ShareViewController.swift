import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Share sheet › Pampu. Reads what was shared into the tray, then works exactly like the app:
/// bring the iPhone close to the Mac (or tap Send) and the sheet closes once it's dropped.
final class ShareViewController: UIViewController {
    private let drop = Drop()

    override func viewDidLoad() {
        super.viewDidLoad()
        drop.onSent = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self?.finish() }
        }
        let root = DropView(drop: drop) { [weak self] in
            Button("Cancel", role: .cancel) { self?.cancel() }
                .font(.body.weight(.medium))
                .padding(.bottom, 2)
        }
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        readAttachments()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        drop.start()
    }

    private func finish() {
        drop.stop()
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func cancel() {
        drop.stop()
        drop.tray.clear()
        extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }

    // MARK: Reading what was shared

    private func readAttachments() {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        for p in providers { read(p) }
    }

    private func read(_ p: NSItemProvider) {
        let types = p.registeredTypeIdentifiers.compactMap(UTType.init)
        let tray = drop.tray

        // Photos, videos, PDFs and other real files.
        let rich = types.first { $0.conforms(to: .image) || $0.conforms(to: .audiovisualContent) || $0.conforms(to: .pdf) }
        let other = types.first { !$0.conforms(to: .text) && !$0.conforms(to: .url) && ($0.conforms(to: .data) || $0.conforms(to: .package)) }
        if let t = rich ?? (types.contains(.fileURL) ? nil : other) {
            tray.loading += 1
            let suggested = p.suggestedName
            _ = p.loadFileRepresentation(forTypeIdentifier: t.identifier) { url, _ in
                // The file is deleted when this returns, so copy it now.
                let staged = url.flatMap { try? Tray.stage($0, name: Self.name(suggested, for: $0)) }
                Task { @MainActor in
                    tray.loading -= 1
                    if let staged { tray.add(staged: staged) }
                }
            }
            return
        }

        // A file from the Files app (or anything shared by location).
        if types.contains(.fileURL) {
            tray.loading += 1
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                let staged = url.flatMap { u -> URL? in
                    let scoped = u.startAccessingSecurityScopedResource()
                    defer { if scoped { u.stopAccessingSecurityScopedResource() } }
                    return try? Tray.stage(u)
                }
                Task { @MainActor in
                    tray.loading -= 1
                    if let staged { tray.add(staged: staged) }
                }
            }
            return
        }

        // A web link, then plain text.
        if p.canLoadObject(ofClass: URL.self) {
            tray.loading += 1
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                let s = url?.absoluteString
                Task { @MainActor in
                    tray.loading -= 1
                    if let s { tray.add(text: s) }
                }
            }
        } else if p.canLoadObject(ofClass: String.self) {
            tray.loading += 1
            _ = p.loadObject(ofClass: String.self) { text, _ in
                Task { @MainActor in
                    tray.loading -= 1
                    if let text { tray.add(text: text) }
                }
            }
        }
    }

    /// The share sheet's suggested name often has no extension; borrow it from the file.
    private nonisolated static func name(_ suggested: String?, for url: URL) -> String {
        guard let s = suggested, !s.isEmpty else { return url.lastPathComponent }
        if (s as NSString).pathExtension.isEmpty, !url.pathExtension.isEmpty { return s + "." + url.pathExtension }
        return s
    }
}
