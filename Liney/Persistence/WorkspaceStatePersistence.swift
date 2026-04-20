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
final class WorkspaceStatePersistence {
    private let fileManager = FileManager.default
    private let saveQueue = DispatchQueue(label: "com.liney.workspace-state.save", qos: .utility)
    private let pendingLock = NSLock()
    private var pendingState: PersistedWorkspaceState?
    private var pendingWorkItem: DispatchWorkItem?
    private let saveDebounce: DispatchTimeInterval = .milliseconds(500)

    func load() -> PersistedWorkspaceState {
        let url = resolvedStateFileURL()
        guard let data = try? Data(contentsOf: url) else {
            return PersistedWorkspaceState(selectedWorkspaceID: nil, workspaces: [])
        }
        do {
            return try JSONDecoder().decode(PersistedWorkspaceState.self, from: data)
        } catch {
            return PersistedWorkspaceState(selectedWorkspaceID: nil, workspaces: [])
        }
    }

    func save(_ state: PersistedWorkspaceState, onError: (@Sendable (Error) -> Void)? = nil) {
        pendingLock.lock()
        pendingState = state
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
            let toSave = pendingState
            pendingState = nil
            pendingLock.unlock()
            guard let toSave else { return }
            try? writeSync(toSave)
        }
    }

    private func drainPendingSave(onError: (@Sendable (Error) -> Void)?) {
        pendingLock.lock()
        let toSave = pendingState
        pendingState = nil
        pendingWorkItem = nil
        pendingLock.unlock()
        guard let toSave else { return }
        do {
            try writeSync(toSave)
        } catch {
            onError?(error)
        }
    }

    private func writeSync(_ state: PersistedWorkspaceState) throws {
        let directory = stateDirectoryURL()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.prettyPrinted.encode(state)
        try data.write(to: stateFileURL(), options: [.atomic])
    }

    private func stateDirectoryURL() -> URL {
        lineyStateDirectoryURL(fileManager: fileManager)
    }

    private func stateFileURL() -> URL {
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

private extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
