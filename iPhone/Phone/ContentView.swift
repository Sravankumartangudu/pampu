import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var drop: Drop
    @AppStorage("compatiblePhotos") private var compatiblePhotos = false
    @State private var picks: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var settings = false

    var body: some View {
        DropView(drop: drop) {
            HStack(spacing: 10) {
                PhotosPicker(selection: $picks, maxSelectionCount: 50, selectionBehavior: .ordered,
                             preferredItemEncoding: compatiblePhotos ? .compatible : .current) {
                    Tile(title: "Photos", symbol: "photo.on.rectangle")
                }
                Button { importing = true } label: { Tile(title: "Files", symbol: "folder") }
                PasteButton(payloadType: String.self) { strings in
                    Task { @MainActor in strings.forEach { drop.tray.add(text: $0) } }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .tint(Theme.blue)
                .frame(height: 58)
                Button { settings = true } label: { Tile(title: "Settings", symbol: "gearshape") }
            }
            .disabled(drop.sender.isSending)
        }
        .onChange(of: picks) { _, items in
            guard !items.isEmpty else { return }
            picks = []
            for item in items { load(item) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            for url in urls { load(url) }
        }
        .sheet(isPresented: $settings) {
            SettingsView(drop: drop, sender: drop.sender, proximity: drop.proximity)
        }
    }

    private func load(_ item: PhotosPickerItem) {
        drop.tray.loading += 1
        Task {
            let file = try? await item.loadTransferable(type: PickedFile.self)
            drop.tray.loading -= 1
            if let file { drop.tray.add(staged: file.url) }
        }
    }

    private func load(_ url: URL) {
        drop.tray.loading += 1
        Task {
            let staged = await Task.detached { () -> URL? in
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                return try? Tray.stage(url)
            }.value
            drop.tray.loading -= 1
            if let staged { drop.tray.add(staged: staged) }
        }
    }
}

/// A photo or video from the picker, copied straight into the outbox.
struct PickedFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { PickedFile(url: try Tray.stage($0.file)) }
        FileRepresentation(importedContentType: .image) { PickedFile(url: try Tray.stage($0.file)) }
        FileRepresentation(importedContentType: .item) { PickedFile(url: try Tray.stage($0.file)) }
    }
}

private struct Tile: View {
    var title: String
    var symbol: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
            Text(title).font(.caption2.weight(.medium))
        }
        .foregroundStyle(Theme.blue)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial))
        .accessibilityElement(children: .combine)
    }
}
