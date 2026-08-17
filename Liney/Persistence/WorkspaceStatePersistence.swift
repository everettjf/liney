//
//  WorkspaceStatePersistence.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

/// Persists workspace state to disk. Writes are coalesced on a background
/// queue so the main thread never spends time JSON-encoding or calling into
/// the filesystem. `flushPendingSync` runs from the app-terminate handler to
/// ensure the latest snapshot is persisted before we exit.
nonisolated final class WorkspaceStatePersistence: @unchecked Sendable {
    private let fileManager: FileManager
    private let stateDirectoryOverride: URL?
    private let saveQueue = DispatchQueue(label: "com.liney.workspace-state.save", qos: .utility)
    private let pendingLock = NSLock()
    private var pendingData: Data?
    private var pendingWorkItem: DispatchWorkItem?
    private let saveDebounce: DispatchTimeInterval = .milliseconds(500)

    init(fileManager: FileManager = .default, stateDirectoryURL: URL? = nil) {
        self.fileManager = fileManager
        self.stateDirectoryOverride = stateDirectoryURL
    }

    @MainActor func load() -> PersistedWorkspaceState {
        loadWithRecovery().value
    }

    @MainActor func loadWithRecovery() -> PersistenceLoadResult<PersistedWorkspaceState> {
        let url = resolvedStateFileURL()
        let primaryExists = fileManager.fileExists(atPath: url.path)
        if primaryExists,
           let data = try? Data(contentsOf: url),
           let value = try? JSONDecoder().decode(PersistedWorkspaceState.self, from: data) {
            return PersistenceLoadResult(value: value, source: .primary)
        }

        let backupURL = RecoverableJSONPersistence.backupURL(for: url)
        if let data = try? Data(contentsOf: backupURL),
           let value = try? JSONDecoder().decode(PersistedWorkspaceState.self, from: data) {
            return PersistenceLoadResult(value: value, source: .backup)
        }

        let defaultValue = PersistedWorkspaceState(selectedWorkspaceID: nil, workspaces: [])
        guard primaryExists else {
            return PersistenceLoadResult(value: defaultValue, source: .missing)
        }
        return PersistenceLoadResult(
            value: defaultValue,
            source: .unrecoverable(
                quarantinedURL: RecoverableJSONPersistence.quarantine(url, fileManager: fileManager)
            )
        )
    }

    @MainActor func save(_ state: PersistedWorkspaceState, onError: (@Sendable (Error) -> Void)? = nil) {
        let data: Data
        do {
            data = try JSONEncoder.prettyPrinted.encode(state)
        } catch {
            onError?(error)
            return
        }
        pendingLock.lock()
        pendingData = data
        pendingWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.drainPendingSave(onError: onError)
        }
        pendingWorkItem = item
        pendingLock.unlock()
        saveQueue.asyncAfter(deadline: .now() + saveDebounce, execute: item)
    }

    /// Synchronously flush any pending save (app quit). Waits for any
    /// in-flight save on the background queue to finish first.
    func flushPendingSync() {
        saveQueue.sync {
            pendingLock.lock()
            pendingWorkItem?.cancel()
            pendingWorkItem = nil
            let toSave = pendingData
            pendingData = nil
            pendingLock.unlock()
            guard let toSave else { return }
            try? writeSync(toSave)
        }
    }

    private func drainPendingSave(onError: (@Sendable (Error) -> Void)?) {
        pendingLock.lock()
        let toSave = pendingData
        pendingData = nil
        pendingWorkItem = nil
        pendingLock.unlock()
        guard let toSave else { return }
        do {
            try writeSync(toSave)
        } catch {
            onError?(error)
        }
    }

    nonisolated private func writeSync(_ data: Data) throws {
        try RecoverableJSONPersistence.write(
            data,
            to: stateFileURL(),
            fileManager: fileManager
        )
    }

    nonisolated private func stateDirectoryURL() -> URL {
        if let stateDirectoryOverride { return stateDirectoryOverride }
        return lineyStateDirectoryURL(fileManager: fileManager)
    }

    nonisolated private func stateFileURL() -> URL {
        stateDirectoryURL().appendingPathComponent("workspace-state.json")
    }

    private func resolvedStateFileURL() -> URL {
        let preferredURL = stateFileURL()
        if fileManager.fileExists(atPath: preferredURL.path) {
            return preferredURL
        }

        let legacyURL = legacyStateFileURL()
        if fileManager.fileExists(atPath: legacyURL.path) {
            return legacyURL
        }

        return preferredURL
    }

    private func legacyStateFileURL() -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("Liney", isDirectory: true)
            .appendingPathComponent("workspace-state.json")
    }
}

nonisolated private extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
