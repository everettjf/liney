//
//  WorkspaceStatePersistence.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

struct WorkspaceStatePersistence {
    private let fileManager = FileManager.default

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

    func save(_ state: PersistedWorkspaceState) throws {
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
