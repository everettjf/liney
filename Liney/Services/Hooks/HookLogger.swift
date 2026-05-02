//
//  HookLogger.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

/// Append-only logger for hook activity. Lives at `~/.liney/hook.log`. Each
/// entry is a single line so users can `tail -f` it. The file is capped to
/// keep it bounded — when it exceeds the limit, the tail is preserved.
///
/// nonisolated for the same reason as HookSettingsPersistence — accessed from
/// the runner's background queue, must not be implicitly MainActor.
nonisolated final class HookLogger: @unchecked Sendable {
    static let shared = HookLogger()

    private let queue = DispatchQueue(label: "com.liney.hook-logger", qos: .utility)
    private let fileManager = FileManager.default
    private let persistence = HookSettingsPersistence()
    private let maxBytes: Int = 256 * 1024  // 256 KB

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    var logFileURL: URL { persistence.logFileURL }

    func log(_ message: String) {
        let timestamp = Self.isoFormatter.string(from: Date())
        let line = "\(timestamp) \(message)\n"
        queue.async { [weak self] in
            self?.append(line)
        }
    }

    func clear() {
        queue.sync {
            try? fileManager.removeItem(at: logFileURL)
        }
    }

    private func append(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        try? fileManager.createDirectory(
            at: persistence.stateDirectoryURL,
            withIntermediateDirectories: true
        )

        if !fileManager.fileExists(atPath: logFileURL.path) {
            try? data.write(to: logFileURL, options: .atomic)
            return
        }

        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } catch {
                // Best-effort logging — swallow.
            }
        }

        rotateIfNeeded()
    }

    private func rotateIfNeeded() {
        guard let attributes = try? fileManager.attributesOfItem(atPath: logFileURL.path),
              let size = attributes[.size] as? Int,
              size > maxBytes else {
            return
        }
        guard let existing = try? Data(contentsOf: logFileURL) else { return }
        let keepFromIndex = max(0, existing.count - maxBytes / 2)
        let trimmed = existing.subdata(in: keepFromIndex..<existing.count)
        let prefix = "--- truncated ---\n".data(using: .utf8) ?? Data()
        try? (prefix + trimmed).write(to: logFileURL, options: .atomic)
    }
}
