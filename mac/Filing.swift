import Foundation
import UniformTypeIdentifiers

/// Decides where a received file goes and moves it there without overwriting anything.
enum Filing {
    enum Kind: String, CaseIterable {
        case photos = "Photos", screenshots = "Screenshots", videos = "Videos", audio = "Audio"
        case documents = "Documents", archives = "Archives", other = "Other"
    }

    static func kind(of name: String) -> Kind {
        let ext = (name as NSString).pathExtension
        guard let type = UTType(filenameExtension: ext) else { return .other }
        let lower = name.lowercased()
        if type.conforms(to: .image) {
            // iPhone screenshots come through the photo picker as PNGs.
            if lower.contains("screenshot") || (type.conforms(to: .png) && lower.hasPrefix("img_")) { return .screenshots }
            return .photos
        }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .videos }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .archive) || type.conforms(to: .zip) || type.conforms(to: .diskImage) { return .archives }
        if type.conforms(to: .pdf) || type.conforms(to: .text) || type.conforms(to: .presentation)
            || type.conforms(to: .spreadsheet) || type.conforms(to: .rtf) || type.conforms(to: .content)
            || ["doc", "docx", "pages", "key", "numbers", "xls", "xlsx", "ppt", "pptx", "epub"].contains(ext.lowercased()) {
            return .documents
        }
        return .other
    }

    static func folder(for name: String, base: URL, sort: Bool) -> URL {
        sort ? base.appendingPathComponent(kind(of: name).rawValue, isDirectory: true) : base
    }

    /// "IMG_1.HEIC" → "IMG_1 2.HEIC" → "IMG_1 3.HEIC" … until the name is free.
    static func unique(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        for n in 2... {
            let candidate = dir.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return url
    }

    /// Moves MultipeerConnectivity's temporary file into place. Must run before the delegate call
    /// returns, because the framework deletes the temporary file afterwards.
    static func file(_ temp: URL, named raw: String, base: URL, sort: Bool) throws -> URL {
        let name = SafeName.clean(raw)
        let dir = folder(for: name, base: base, sort: sort)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = unique(dir.appendingPathComponent(name))
        try FileManager.default.moveItem(at: temp, to: dest)
        return dest
    }
}
