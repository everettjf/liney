//
//  RecoverableJSONPersistence.swift
//  Liney
//

import Foundation

nonisolated enum PersistenceLoadSource: Equatable, Sendable {
    case primary
    case backup
    case missing
    case unrecoverable(quarantinedURL: URL?)
}

nonisolated struct PersistenceLoadResult<Value> {
    let value: Value
    let source: PersistenceLoadSource
}

nonisolated enum RecoverableJSONPersistence {
    static func backupURL(for primaryURL: URL) -> URL {
        primaryURL.appendingPathExtension("backup")
    }

    static func write(
        _ data: Data,
        to primaryURL: URL,
        fileManager: FileManager = .default,
    ) throws {
        try fileManager.createDirectory(
            at: primaryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try data.write(to: primaryURL, options: .atomic)
        try data.write(to: backupURL(for: primaryURL), options: .atomic)
    }

    static func quarantine(_ primaryURL: URL, fileManager: FileManager) -> URL? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let quarantineURL = primaryURL.appendingPathExtension("corrupt-\(timestamp)-\(UUID().uuidString.prefix(8))")
        do {
            try fileManager.moveItem(at: primaryURL, to: quarantineURL)
            return quarantineURL
        } catch {
            return nil
        }
    }
}
