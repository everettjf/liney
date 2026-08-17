//
//  AppSettingsPersistence.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

nonisolated private let lineyPersistenceIsDebugBuild: Bool = {
#if DEBUG
    true
#else
    false
#endif
}()

nonisolated func lineyStateDirectoryName(isDebugBuild: Bool = lineyPersistenceIsDebugBuild) -> String {
    isDebugBuild ? ".liney-debug" : ".liney"
}

nonisolated func lineyStateDirectoryURL(fileManager: FileManager = .default) -> URL {
    fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
        lineyStateDirectoryName(),
        isDirectory: true
    )
}

/// Coalesced, off-main persistence for AppSettings. Mirrors
/// WorkspaceStatePersistence so hot paths that touch settings (e.g. every
/// workspace refresh calls persistAppSettings) don't pay for a JSON encode
/// and a synchronous disk write on the main thread.
nonisolated final class AppSettingsPersistence: @unchecked Sendable {
    private let fileManager: FileManager
    private let stateDirectoryOverride: URL?
    private let saveQueue = DispatchQueue(label: "com.liney.app-settings.save", qos: .utility)
    private let pendingLock = NSLock()
    private var pendingData: Data?
    private var pendingWorkItem: DispatchWorkItem?
    private let saveDebounce: DispatchTimeInterval = .milliseconds(500)

    init(fileManager: FileManager = .default, stateDirectoryURL: URL? = nil) {
        self.fileManager = fileManager
        self.stateDirectoryOverride = stateDirectoryURL
    }

    @MainActor func load() -> AppSettings {
        loadWithRecovery().value
    }

    @MainActor func loadWithRecovery() -> PersistenceLoadResult<AppSettings> {
        let url = resolvedSettingsFileURL()
        let primaryExists = fileManager.fileExists(atPath: url.path)
        if primaryExists,
           let data = try? Data(contentsOf: url),
           let value = try? JSONDecoder().decode(AppSettings.self, from: data) {
            return PersistenceLoadResult(value: value, source: .primary)
        }

        let backupURL = RecoverableJSONPersistence.backupURL(for: url)
        if let data = try? Data(contentsOf: backupURL),
           let value = try? JSONDecoder().decode(AppSettings.self, from: data) {
            return PersistenceLoadResult(value: value, source: .backup)
        }

        guard primaryExists else {
            return PersistenceLoadResult(value: AppSettings(), source: .missing)
        }
        return PersistenceLoadResult(
            value: AppSettings(),
            source: .unrecoverable(
                quarantinedURL: RecoverableJSONPersistence.quarantine(url, fileManager: fileManager)
            )
        )
    }

    @MainActor func save(_ settings: AppSettings, onError: (@Sendable (Error) -> Void)? = nil) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(settings)
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

    /// Synchronously flush any pending settings save. Called from the
    /// app-terminate handler so the latest settings land on disk before exit.
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
            to: settingsFileURL(),
            fileManager: fileManager
        )
    }

    nonisolated private func stateDirectoryURL() -> URL {
        if let stateDirectoryOverride { return stateDirectoryOverride }
        return lineyStateDirectoryURL(fileManager: fileManager)
    }

    nonisolated private func settingsFileURL() -> URL {
        stateDirectoryURL().appendingPathComponent("settings.json")
    }

    private func resolvedSettingsFileURL() -> URL {
        let preferredURL = settingsFileURL()
        if fileManager.fileExists(atPath: preferredURL.path) {
            return preferredURL
        }

        let legacyURL = legacySettingsFileURL()
        if fileManager.fileExists(atPath: legacyURL.path) {
            return legacyURL
        }

        return preferredURL
    }

    private func legacySettingsFileURL() -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("Liney", isDirectory: true)
            .appendingPathComponent("settings.json")
    }
}
