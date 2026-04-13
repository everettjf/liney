//
//  GitHistoryCommit.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

struct GitHistoryCommit: Identifiable, Hashable, Sendable {
    let hash: String
    let shortHash: String
    let authorName: String
    let authorEmail: String
    let authorDate: Date
    let subject: String
    let body: String
    let parentCount: Int
    let insertions: Int
    let deletions: Int

    var id: String { hash }

    var isMergeCommit: Bool { parentCount > 1 }

    var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: authorDate, relativeTo: Date())
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: authorDate)
    }

    var fullMessage: String {
        body.isEmpty ? subject : "\(subject)\n\n\(body)"
    }

    var statsDescription: String {
        if insertions == 0 && deletions == 0 { return "" }
        var parts: [String] = []
        if insertions > 0 { parts.append("+\(insertions)") }
        if deletions > 0 { parts.append("-\(deletions)") }
        return parts.joined(separator: " ")
    }

    /// Matches query against subject, author name, author email, and short hash.
    func matches(query: String) -> Bool {
        let q = query.lowercased()
        return subject.lowercased().contains(q)
            || authorName.lowercased().contains(q)
            || authorEmail.lowercased().contains(q)
            || shortHash.lowercased().contains(q)
            || hash.lowercased().hasPrefix(q)
    }

    // MARK: - Parsing

    private static let separator = "---COMMIT---"
    private static let fieldSeparator = "---FIELD---"
    private static let iso8601 = ISO8601DateFormatter()

    /// Parse the output of `git log` with our custom format.
    /// Format: ---COMMIT---<hash>---FIELD---<short>---FIELD---<name>---FIELD---<email>---FIELD---<dateISO>---FIELD---<subject>---FIELD---<body>---FIELD---<parents>
    static func parseLog(_ output: String) -> [GitHistoryCommit] {
        return output
            .components(separatedBy: separator)
            .compactMap { block in
                let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                let fields = trimmed.components(separatedBy: fieldSeparator)
                guard fields.count >= 8 else { return nil }
                let hash = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !hash.isEmpty else { return nil }
                let shortHash = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let authorName = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
                let authorEmail = fields[3].trimmingCharacters(in: .whitespacesAndNewlines)
                let dateString = fields[4].trimmingCharacters(in: .whitespacesAndNewlines)
                let subject = fields[5].trimmingCharacters(in: .whitespacesAndNewlines)
                let body = fields[6].trimmingCharacters(in: .whitespacesAndNewlines)
                let parentString = fields[7].trimmingCharacters(in: .whitespacesAndNewlines)
                let parentCount = parentString.isEmpty ? 0 : parentString.split(separator: " ").count
                let date = iso8601.date(from: dateString) ?? Date.distantPast
                return GitHistoryCommit(
                    hash: hash,
                    shortHash: shortHash,
                    authorName: authorName,
                    authorEmail: authorEmail,
                    authorDate: date,
                    subject: subject,
                    body: body,
                    parentCount: parentCount,
                    insertions: 0,
                    deletions: 0
                )
            }
    }

    /// Parse numstat summary to get insertions/deletions per commit.
    /// Input: output from `git log --numstat --format="---COMMIT---%H"`.
    static func enrichWithStats(_ commits: [GitHistoryCommit], numstatOutput: String) -> [GitHistoryCommit] {
        var statsMap: [String: (ins: Int, del: Int)] = [:]
        let blocks = numstatOutput.components(separatedBy: separator)
        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true)
            guard let first = lines.first else { continue }
            let hash = first.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !hash.isEmpty else { continue }
            var ins = 0
            var del = 0
            for line in lines.dropFirst() {
                let parts = line.split(separator: "\t")
                guard parts.count >= 2 else { continue }
                ins += Int(parts[0]) ?? 0
                del += Int(parts[1]) ?? 0
            }
            statsMap[hash] = (ins, del)
        }
        return commits.map { commit in
            if let stats = statsMap[commit.hash] {
                return GitHistoryCommit(
                    hash: commit.hash,
                    shortHash: commit.shortHash,
                    authorName: commit.authorName,
                    authorEmail: commit.authorEmail,
                    authorDate: commit.authorDate,
                    subject: commit.subject,
                    body: commit.body,
                    parentCount: commit.parentCount,
                    insertions: stats.ins,
                    deletions: stats.del
                )
            }
            return commit
        }
    }
}

// MARK: - Blame

struct GitBlameLine: Identifiable, Sendable {
    let id: Int  // line number (1-based)
    let commitHash: String
    let shortHash: String
    let author: String
    let date: String
    let lineContent: String

    static func parseBlame(_ output: String) -> [GitBlameLine] {
        var lines: [GitBlameLine] = []
        var lineNumber = 1
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            // git blame --porcelain style is complex; use line-porcelain
            // But simpler: parse default format: "hash (author date lineNo) content"
            // We use `git blame --line-porcelain` and parse it.
            // For simple parsing, use `git blame` default output format.
            guard !line.isEmpty else {
                lines.append(GitBlameLine(id: lineNumber, commitHash: "", shortHash: "", author: "", date: "", lineContent: ""))
                lineNumber += 1
                continue
            }
            // Default git blame format: "^?shortHash (Author       Date                  lineNo) content"
            // We'll parse custom format from `git blame --porcelain`
            lines.append(GitBlameLine(id: lineNumber, commitHash: "", shortHash: "", author: "", date: "", lineContent: line))
            lineNumber += 1
        }
        return lines
    }

    /// Parse `git blame --line-porcelain` output.
    static func parseLinePorcelain(_ output: String) -> [GitBlameLine] {
        var result: [GitBlameLine] = []
        var currentHash = ""
        var currentAuthor = ""
        var currentDate = ""
        var lineNumber = 0

        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var i = 0
        while i < lines.count {
            let line = lines[i]
            // A commit line starts with 40-char hex hash
            if line.count >= 40, line.prefix(40).allSatisfy({ $0.isHexDigit }) {
                let parts = line.split(separator: " ")
                currentHash = String(parts[0])
                if parts.count >= 3 {
                    lineNumber = Int(parts[2]) ?? (lineNumber + 1)
                } else {
                    lineNumber += 1
                }
                i += 1
                // Read header lines until we hit a tab-prefixed content line
                while i < lines.count {
                    let headerLine = lines[i]
                    if headerLine.hasPrefix("\t") {
                        // Content line
                        let content = String(headerLine.dropFirst())
                        let shortHash = String(currentHash.prefix(7))
                        result.append(GitBlameLine(
                            id: lineNumber,
                            commitHash: currentHash,
                            shortHash: shortHash,
                            author: currentAuthor,
                            date: currentDate,
                            lineContent: content
                        ))
                        i += 1
                        break
                    } else if headerLine.hasPrefix("author ") {
                        currentAuthor = String(headerLine.dropFirst("author ".count))
                    } else if headerLine.hasPrefix("author-time ") {
                        let timestamp = TimeInterval(headerLine.dropFirst("author-time ".count)) ?? 0
                        let date = Date(timeIntervalSince1970: timestamp)
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd"
                        currentDate = formatter.string(from: date)
                    }
                    i += 1
                }
            } else {
                i += 1
            }
        }
        return result
    }
}
