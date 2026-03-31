//
//  WorkspaceFileBrowserSupport.swift
//  Liney
//

import Foundation

nonisolated struct WorkspaceFileBrowserEntry: Identifiable, Hashable, Sendable {
    let path: String
    let relativePath: String
    let fileName: String
    let fileSize: Int64

    var id: String { path }
}

nonisolated enum WorkspaceFileBrowserPreview: Equatable, Sendable {
    case text(String)
    case unsupported(reason: String)
}

nonisolated enum WorkspaceFileBrowserSupport {
    static let maxEnumerationResults = 4_000
    static let maxPreviewBytes = 256 * 1_024

    nonisolated static func enumerateFiles(
        in rootPath: String,
        maxResults: Int = maxEnumerationResults
    ) throws -> [WorkspaceFileBrowserEntry] {
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
        let resolvedRootPath = rootURL.resolvingSymlinksInPath().standardizedFileURL.path
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey],
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        var entries: [WorkspaceFileBrowserEntry] = []

        while let candidateURL = enumerator.nextObject() as? URL {
            if candidateURL.pathComponents.contains(".git") {
                if candidateURL.hasDirectoryPath {
                    enumerator.skipDescendants()
                }
                continue
            }

            let resourceValues = try candidateURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey])

            guard resourceValues.isRegularFile == true else { continue }

            let relativePath = relativePathForCandidate(
                candidateURL,
                resolvedRootPath: resolvedRootPath
            )
            entries.append(
                WorkspaceFileBrowserEntry(
                    path: candidateURL.path,
                    relativePath: relativePath,
                    fileName: candidateURL.lastPathComponent,
                    fileSize: Int64(resourceValues.fileSize ?? 0)
                )
            )

            if entries.count >= maxResults {
                break
            }
        }

        return entries.sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
    }

    nonisolated static func loadPreview(
        at path: String,
        maxBytes: Int = maxPreviewBytes
    ) throws -> WorkspaceFileBrowserPreview {
        let fileURL = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: fileURL)

        if data.count > maxBytes {
            return .unsupported(reason: "large")
        }

        guard let text = String(data: data, encoding: .utf8) else {
            return .unsupported(reason: "binary")
        }

        return .text(text)
    }

    nonisolated static func saveTextFile(contents: String, to path: String) throws {
        try contents.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
    }

    private nonisolated static func relativePathForCandidate(
        _ candidateURL: URL,
        resolvedRootPath: String
    ) -> String {
        let resolvedCandidatePath = candidateURL.resolvingSymlinksInPath().standardizedFileURL.path
        if resolvedCandidatePath == resolvedRootPath {
            return candidateURL.lastPathComponent
        }

        let prefix = resolvedRootPath.hasSuffix("/") ? resolvedRootPath : resolvedRootPath + "/"
        if resolvedCandidatePath.hasPrefix(prefix) {
            return String(resolvedCandidatePath.dropFirst(prefix.count))
        }

        return candidateURL.lastPathComponent
    }
}
