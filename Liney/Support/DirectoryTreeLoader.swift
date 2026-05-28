//
//  DirectoryTreeLoader.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

/// One entry in the workspace directory tree.
nonisolated struct DirectoryTreeEntry: Identifiable, Hashable {
    let url: URL
    let name: String
    let isDirectory: Bool

    var id: String { url.path }

    /// `true` when this file can be rendered in the preview panel.
    var isPreviewable: Bool {
        !isDirectory && WorkspacePreviewContent.isPreviewable(url)
    }

    /// SF Symbol representing the entry in the tree.
    var symbolName: String {
        if isDirectory { return "folder.fill" }
        let ext = url.pathExtension.lowercased()
        if WorkspacePreviewContent.markdownExtensions.contains(ext) { return "doc.richtext" }
        if WorkspacePreviewContent.htmlExtensions.contains(ext) { return "chevron.left.forwardslash.chevron.right" }
        switch ext {
        case "swift": return "swift"
        case "json", "yaml", "yml", "toml", "plist": return "curlybraces"
        case "png", "jpg", "jpeg", "gif", "svg", "webp", "heic": return "photo"
        case "sh", "bash", "zsh", "fish": return "terminal"
        case "js", "ts", "jsx", "tsx", "py", "rb", "go", "rs", "c", "cpp", "h", "java", "kt": return "chevron.left.forwardslash.chevron.right"
        default: return "doc.text"
        }
    }
}

/// Lists directory contents for the file-tree column.
///
/// Pure and synchronous so it can be unit-tested and called off the main thread.
/// Hidden entries are excluded unless `includesHidden` is set; directories sort
/// before files, then case-insensitive by name.
nonisolated enum DirectoryTreeLoader {

    static func entries(at directoryURL: URL, includesHidden: Bool = false) -> [DirectoryTreeEntry] {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .nameKey]
        var options: FileManager.DirectoryEnumerationOptions = [.skipsSubdirectoryDescendants]
        if !includesHidden { options.insert(.skipsHiddenFiles) }

        guard let contents = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: keys,
            options: options
        ) else {
            return []
        }

        let mapped: [DirectoryTreeEntry] = contents.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isDirectory = values?.isDirectory ?? false
            let name = values?.name ?? url.lastPathComponent
            // Keep the original (unresolved) URL: an entry's identity is its
            // path, so resolving symlinks would make a link and its target
            // collide on `id` and render one row blank. Open/preview/reveal
            // follow the link at the filesystem level regardless.
            return DirectoryTreeEntry(url: url, name: name, isDirectory: isDirectory)
        }

        return sort(mapped)
    }

    /// Directories first, then case-insensitive alphabetical.
    static func sort(_ entries: [DirectoryTreeEntry]) -> [DirectoryTreeEntry] {
        entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// Whether a path points at a readable directory.
    static func isReadableDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}
