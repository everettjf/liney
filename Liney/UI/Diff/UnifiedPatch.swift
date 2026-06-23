//
//  UnifiedPatch.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

/// A single hunk within a file section of a unified diff.
struct PatchHunk: Identifiable, Hashable {
    /// Stable id of the form `<path>#<index>` (or `<path>#whole`).
    let id: String
    /// The `@@ -a,b +c,d @@` header line, or a synthetic label for whole-file changes.
    let header: String
    /// The hunk body (context / `+` / `-` / `\` lines). Empty for whole-file hunks
    /// whose content lives in the section header (binary or mode-only changes).
    let bodyLines: [String]
    /// True when the change cannot be split further and the whole section header
    /// carries the payload (binary patches, pure mode changes).
    let isWholeFile: Bool

    var addedCount: Int { bodyLines.filter { $0.hasPrefix("+") }.count }
    var removedCount: Int { bodyLines.filter { $0.hasPrefix("-") }.count }
}

/// One file's section within a unified diff: the `diff --git` header plus its hunks.
struct PatchFileSection: Identifiable, Hashable {
    /// Stable id (the file's new/target path).
    let id: String
    let path: String
    /// Everything before the first `@@` hunk (`diff --git`, `index`, `---`, `+++`,
    /// and for binary/mode changes the entire payload).
    let headerLines: [String]
    let hunks: [PatchHunk]
}

/// Parses and reassembles unified diffs so callers can cherry-pick individual
/// hunks. Pure string manipulation — no git invocation.
enum UnifiedPatch {
    /// Splits a `git diff` patch into per-file sections and hunks.
    static func parse(_ patch: String) -> [PatchFileSection] {
        guard !patch.isEmpty else { return [] }
        var lines = patch.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }

        var sections: [PatchFileSection] = []
        var index = 0
        while index < lines.count {
            guard lines[index].hasPrefix("diff --git ") else {
                index += 1
                continue
            }
            var sectionLines = [lines[index]]
            index += 1
            while index < lines.count, !lines[index].hasPrefix("diff --git ") {
                sectionLines.append(lines[index])
                index += 1
            }
            sections.append(makeSection(sectionLines))
        }
        return sections
    }

    /// Rebuilds a valid patch containing only the selected hunks. Sections with no
    /// selected hunk are dropped entirely.
    static func reassemble(selectedHunkIDs: Set<String>, from sections: [PatchFileSection]) -> String {
        var output: [String] = []
        for section in sections {
            let selected = section.hunks.filter { selectedHunkIDs.contains($0.id) }
            guard !selected.isEmpty else { continue }
            output.append(contentsOf: section.headerLines)
            for hunk in selected where !hunk.isWholeFile {
                output.append(hunk.header)
                output.append(contentsOf: hunk.bodyLines)
            }
        }
        guard !output.isEmpty else { return "" }
        return output.joined(separator: "\n") + "\n"
    }

    // MARK: - Parsing helpers

    private static func makeSection(_ lines: [String]) -> PatchFileSection {
        let path = parsePath(fromDiffLine: lines.first ?? "")

        var headerEnd = lines.count
        for (offset, line) in lines.enumerated() where line.hasPrefix("@@ ") {
            headerEnd = offset
            break
        }
        let headerLines = Array(lines[0..<headerEnd])

        guard headerEnd < lines.count else {
            // No `@@` hunk: binary or mode-only change → a single whole-file hunk.
            let hunk = PatchHunk(
                id: path + "#whole",
                header: wholeFileLabel(headerLines),
                bodyLines: [],
                isWholeFile: true
            )
            return PatchFileSection(id: path, path: path, headerLines: headerLines, hunks: [hunk])
        }

        var hunks: [PatchHunk] = []
        var index = headerEnd
        var hunkIndex = 0
        while index < lines.count {
            guard lines[index].hasPrefix("@@ ") else {
                index += 1
                continue
            }
            let header = lines[index]
            var body: [String] = []
            index += 1
            while index < lines.count, !lines[index].hasPrefix("@@ ") {
                body.append(lines[index])
                index += 1
            }
            hunks.append(
                PatchHunk(id: "\(path)#\(hunkIndex)", header: header, bodyLines: body, isWholeFile: false)
            )
            hunkIndex += 1
        }
        return PatchFileSection(id: path, path: path, headerLines: headerLines, hunks: hunks)
    }

    private static func parsePath(fromDiffLine line: String) -> String {
        let prefix = "diff --git "
        guard line.hasPrefix(prefix) else { return line }
        let rest = String(line.dropFirst(prefix.count))
        if let range = rest.range(of: " b/", options: .backwards) {
            return unquote(String(rest[range.upperBound...]))
        }
        return rest
    }

    private static func unquote(_ path: String) -> String {
        guard path.hasPrefix("\""), path.hasSuffix("\""), path.count >= 2 else { return path }
        return String(path.dropFirst().dropLast())
    }

    private static func wholeFileLabel(_ headerLines: [String]) -> String {
        if headerLines.contains(where: { $0.hasPrefix("Binary files") || $0 == "GIT binary patch" }) {
            return "Binary file"
        }
        return "File change"
    }
}
