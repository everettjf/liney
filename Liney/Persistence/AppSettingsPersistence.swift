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

struct AppSettingsPersistence {
    private let fileManager = FileManager.default

    func load() -> AppSettings {
        let url = resolvedSettingsFileURL()
        guard let data = try? Data(contentsOf: url) else {
            return AppSettings()
        }
        return (try? JSONDecoder().decode(AppSettings.self, from: data)) ?? AppSettings()
    }

    func save(_ settings: AppSettings) throws {
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
