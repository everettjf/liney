//
//  AppSettingsPersistence.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

private let lineyPersistenceIsDebugBuild: Bool = {
#if DEBUG
    true
#else
    false
#endif
}()

func lineyStateDirectoryName(isDebugBuild: Bool = lineyPersistenceIsDebugBuild) -> String {
    isDebugBuild ? ".liney-debug" : ".liney"
}

func lineyStateDirectoryURL(fileManager: FileManager = .default) -> URL {
    fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
        lineyStateDirectoryName(),
        isDirectory: true
    )
}

/// Coalesced, off-main persistence for AppSettings. Mirrors
/// WorkspaceStatePersistence so hot paths that touch settings (e.g. every
/// workspace refresh calls persistAppSettings) don't pay for a JSON encode
/// and a synchronous disk write on the main thread.
final class AppSettingsPersistence {
    private let fileManager = FileManager.default
    private let saveQueue = DispatchQueue(label: "com.liney.app-settings.save", qos: .utility)
    private let pendingLock = NSLock()
    private var pendingSettings: AppSettings?
    private var pendingWorkItem: DispatchWorkItem?
    private let saveDebounce: DispatchTimeInterval = .milliseconds(500)

    func load() -> AppSettings {
        let url = resolvedSettingsFileURL()
        guard let data = try? Data(contentsOf: url) else {
            return AppSettings()
        }
        return (try? JSONDecoder().decode(AppSettings.self, from: data)) ?? AppSettings()
    }

    func save(_ settings: AppSettings, onError: (@Sendable (Error) -> Void)? = nil) {
        pendingLock.lock()
        pendingSettings = settings
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
            let toSave = pendingSettings
            pendingSettings = nil
            pendingLock.unlock()
            guard let toSave else { return }
            try? writeSync(toSave)
        }
    }

    private func drainPendingSave(onError: (@Sendable (Error) -> Void)?) {
        pendingLock.lock()
        let toSave = pendingSettings
        pendingSettings = nil
        pendingWorkItem = nil
        pendingLock.unlock()
        guard let toSave else { return }
        do {
            try writeSync(toSave)
        } catch {
            onError?(error)
        }
    }

    private func writeSync(_ settings: AppSettings) throws {
        let directory = stateDirectoryURL()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: settingsFileURL(), options: Data.WritingOptions.atomic)
    }

    private func stateDirectoryURL() -> URL {
        lineyStateDirectoryURL(fileManager: fileManager)
    }

    private func settingsFileURL() -> URL {
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
