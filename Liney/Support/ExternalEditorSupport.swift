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
        let bundleIndex = scanApplicationBundles()
        return ExternalEditor.allCases.compactMap { editor in
            descriptor(for: editor, bundleIndex: bundleIndex)
        }
    }

    nonisolated static func descriptor(for editor: ExternalEditor) -> ExternalEditorDescriptor? {
        descriptor(for: editor, bundleIndex: scanApplicationBundles())
    }

    nonisolated private static func descriptor(
        for editor: ExternalEditor,
        bundleIndex: [String: URL]
    ) -> ExternalEditorDescriptor? {
        for applicationName in editor.applicationNames {
            let bundleName = applicationName.hasSuffix(".app") ? applicationName : "\(applicationName).app"
            if let url = bundleIndex[bundleName] {
                return ExternalEditorDescriptor(
                    editor: editor,
                    applicationName: applicationName,
                    applicationPath: url.path
                )
            }
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

    @MainActor
    static func openSSHRemote(
        sshConfiguration: SSHSessionConfiguration,
        completion: @escaping (Result<Void, any Error>) -> Void
    ) {
        let cliPath = vsCodeCLIPath()
        guard let cliPath else {
            completion(.failure(CocoaError(.fileNoSuchFile, userInfo: [
                NSLocalizedDescriptionKey: "VS Code CLI not found. Install VS Code and ensure the app is in /Applications."
            ])))
            return
        }
        let destination = sshConfiguration.destination
        let remotePath = sshConfiguration.remoteWorkingDirectory ?? "~"
        let remoteArg = "ssh-remote+\(destination)"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: cliPath)
        task.arguments = ["--remote", remoteArg, remotePath]
        do {
            try task.run()
            completion(.success(()))
        } catch {
            completion(.failure(error))
        }
    }

    nonisolated private static func vsCodeCLIPath() -> String? {
        let candidates = [
            "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code",
            "/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/bin/code-insiders",
            "/Applications/Cursor.app/Contents/Resources/app/bin/cursor",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    /// Enumerate each search root once, indexing every `.app` bundle we find
    /// by its last path component. Matching all editors against this dictionary
    /// replaces the previous O(N_editors × full_walk) scan.
    nonisolated private static func scanApplicationBundles() -> [String: URL] {
        let fileManager = FileManager.default
        var index: [String: URL] = [:]
        for root in applicationSearchRoots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }
            let baseDepth = root.pathComponents.count
            while let candidateURL = enumerator.nextObject() as? URL {
                let lastComponent = candidateURL.lastPathComponent
                if lastComponent.hasSuffix(".app") {
                    if index[lastComponent] == nil {
                        index[lastComponent] = candidateURL
                    }
                    // skipsPackageDescendants already prevents descent into the bundle.
                    continue
                }
                let depth = candidateURL.pathComponents.count - baseDepth
                if depth >= 3 {
                    enumerator.skipDescendants()
                }
            }
        }
        return index
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
