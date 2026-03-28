//
//  ExternalEditorSupport.swift
//  Liney
//
//  Author: everettjf
//

import AppKit
import Foundation

struct ExternalEditorDescriptor: Hashable, Identifiable {
    let editor: ExternalEditor
    let applicationName: String
    let applicationPath: String

    var id: ExternalEditor { editor }
    var applicationURL: URL { URL(fileURLWithPath: applicationPath) }
}

enum ExternalEditorCatalog {
    nonisolated static func availableEditors() -> [ExternalEditorDescriptor] {
        ExternalEditor.allCases.compactMap(descriptor(for:))
    }

    nonisolated static func descriptor(for editor: ExternalEditor) -> ExternalEditorDescriptor? {
        for applicationName in editor.applicationNames {
            guard let applicationURL = applicationURL(named: applicationName) else { continue }
            return ExternalEditorDescriptor(
                editor: editor,
                applicationName: applicationName,
                applicationPath: applicationURL.path
            )
        }
        return nil
    }

    nonisolated static func effectiveEditor(
        preferred: ExternalEditor,
        among availableEditors: [ExternalEditorDescriptor]
    ) -> ExternalEditorDescriptor? {
        availableEditors.first(where: { $0.editor == preferred }) ?? availableEditors.first
    }

    nonisolated static func effectiveEditor(preferred: ExternalEditor) -> ExternalEditorDescriptor? {
        effectiveEditor(preferred: preferred, among: availableEditors())
    }

    @MainActor
    static func open(
        _ directoryURL: URL,
        in editor: ExternalEditorDescriptor,
        workspace: NSWorkspace = .shared,
        completion: @escaping (Result<Void, any Error>) -> Void
    ) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.open([directoryURL], withApplicationAt: editor.applicationURL, configuration: configuration) { _, error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    nonisolated private static func applicationURL(named applicationName: String) -> URL? {
        let fileManager = FileManager.default
        let bundleName = applicationName.hasSuffix(".app") ? applicationName : "\(applicationName).app"

        for root in applicationSearchRoots {
            let directMatch = root.appendingPathComponent(bundleName, isDirectory: true)
            if fileManager.fileExists(atPath: directMatch.path) {
                return directMatch
            }

            if let nestedMatch = nestedApplicationURL(named: bundleName, under: root) {
                return nestedMatch
            }
        }

        return nil
    }

    nonisolated private static func nestedApplicationURL(named bundleName: String, under root: URL) -> URL? {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }

        let baseDepth = root.pathComponents.count
        while let candidateURL = enumerator.nextObject() as? URL {
            let depth = candidateURL.pathComponents.count - baseDepth
            if depth > 3 {
                enumerator.skipDescendants()
                continue
            }

            if candidateURL.lastPathComponent == bundleName {
                return candidateURL
            }
        }

        return nil
    }

    nonisolated private static var applicationSearchRoots: [URL] {
        let fileManager = FileManager.default
        return [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        ]
    }
}

private extension ExternalEditor {
    nonisolated var applicationNames: [String] {
        switch self {
        case .cursor:
            return ["Cursor"]
        case .iTerm2:
            return ["iTerm", "iTerm2"]
        case .terminal:
            return ["Terminal"]
        case .ghostty:
            return ["Ghostty"]
        case .zed:
            return ["Zed"]
        case .visualStudioCode:
            return ["Visual Studio Code"]
        case .visualStudioCodeInsiders:
            return ["Visual Studio Code - Insiders", "Visual Studio Code Insiders"]
        case .windsurf:
            return ["Windsurf"]
        case .fleet:
            return ["Fleet"]
        case .xcode:
            return ["Xcode"]
        case .nova:
            return ["Nova"]
        case .sublimeText:
            return ["Sublime Text"]
        }
    }
}
