//
//  HookSettingsPersistence.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

/// Loads, writes, and locates the hook configuration file at
/// `~/.liney/hooks.json` (or the debug variant). Independent from
/// `AppSettingsPersistence` because hook commands are an executable surface
/// that benefits from a separate, easily auditable file.
///
/// Marked nonisolated — the project's default actor isolation is MainActor,
/// but this type is plain stateless I/O and is read from background queues
/// by `HookRunner`. Without `nonisolated` the implicit MainActor isolation
/// would hand off deinit to the main actor, which corrupts the heap when the
/// runner releases its reference from a queue thread.
nonisolated final class HookSettingsPersistence: @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    var stateDirectoryURL: URL {
        lineyStateDirectoryURL(fileManager: fileManager)
    }

    var fileURL: URL {
        stateDirectoryURL.appendingPathComponent("hooks.json", isDirectory: false)
    }

    var logFileURL: URL {
        stateDirectoryURL.appendingPathComponent("hook.log", isDirectory: false)
    }

    /// Returns nil when the file does not exist yet. Treats parse errors as
    /// "no hooks configured" rather than a fatal — the caller will still log.
    func load() -> HookSettings? {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(HookSettings.self, from: data)
        } catch {
            HookLogger.shared.log("Failed to parse \(fileURL.path): \(error)")
            return nil
        }
    }

    /// Returns the file's last-modified timestamp, used for cache invalidation.
    func modificationDate() -> Date? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path) else {
            return nil
        }
        return attributes[.modificationDate] as? Date
    }

    /// Write the given settings to disk. Used to scaffold the file on first use.
    func write(_ settings: HookSettings) throws {
        try fileManager.createDirectory(
            at: stateDirectoryURL,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Create `hooks.json` with sample (disabled) commands if it does not exist.
    /// Returns true when a fresh file was just created.
    @discardableResult
    func ensureFileExists() throws -> Bool {
        if fileManager.fileExists(atPath: fileURL.path) {
            return false
        }
        try write(.sample)
        return true
    }
}
