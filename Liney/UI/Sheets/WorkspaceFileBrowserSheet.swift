//
//  WorkspaceFileBrowserSheet.swift
//  Liney
//

import SwiftUI

struct WorkspaceFileBrowserSheet: View {
    private enum PreviewState: Equatable {
        case idle
        case loading
        case text(String)
        case unsupported(String)
        case failed(String)
    }

    let request: WorkspaceFileBrowserRequest

    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var localization = LocalizationManager.shared

    @State private var searchQuery = ""
    @State private var files: [WorkspaceFileBrowserEntry] = []
    @State private var selectedFilePath: String?
    @State private var previewState: PreviewState = .idle
    @State private var editableContents = ""
    @State private var lastLoadedContents = ""
    @State private var isLoadingFiles = false

    private func localized(_ key: String) -> String {
        localization.string(key)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        l10nFormat(localized(key), locale: .current, arguments: arguments)
    }

    private var filteredFiles: [WorkspaceFileBrowserEntry] {
        let normalizedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return files }
        return files.filter {
            $0.relativePath.localizedCaseInsensitiveContains(normalizedQuery) ||
            $0.fileName.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    private var selectedEntry: WorkspaceFileBrowserEntry? {
        guard let selectedFilePath else { return nil }
        return files.first(where: { $0.path == selectedFilePath })
    }

    private var hasUnsavedChanges: Bool {
        previewState == .text(lastLoadedContents) && editableContents != lastLoadedContents
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 10) {
                TextField(localized("sheet.fileBrowser.searchPlaceholder"), text: $searchQuery)
                    .textFieldStyle(.roundedBorder)

                if isLoadingFiles {
                    Spacer()
                    ProgressView(localized("sheet.fileBrowser.loading"))
                    Spacer()
                } else if filteredFiles.isEmpty {
                    Spacer()
                    ContentUnavailableView(
                        localized("sheet.fileBrowser.emptyTitle"),
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(localized("sheet.fileBrowser.emptyDescription"))
                    )
                    Spacer()
                } else {
                    List(filteredFiles, selection: $selectedFilePath) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.fileName)
                                .font(.system(size: 13, weight: .semibold))
                            Text(entry.relativePath)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(LineyTheme.secondaryText)
                                .lineLimit(1)
                        }
                        .tag(entry.path)
                    }
                    .listStyle(.sidebar)
                }
            }
            .padding(16)
            .frame(minWidth: 300, maxWidth: 360, maxHeight: .infinity)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(request.workspaceName)
                            .font(.title3.weight(.semibold))
                        Text(request.rootPath)
                            .font(.caption.monospaced())
                            .foregroundStyle(LineyTheme.secondaryText)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Label(localized("common.ok"), systemImage: "checkmark")
                    }
                }

                if let entry = selectedEntry {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(entry.fileName)
                                .font(.headline)
                            if hasUnsavedChanges {
                                Text(localized("sheet.fileBrowser.unsaved"))
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(LineyTheme.warning.opacity(0.16), in: Capsule())
                                    .foregroundStyle(LineyTheme.warning)
                            }
                            Spacer()
                        }
                        Text(entry.relativePath)
                            .font(.caption.monospaced())
                            .foregroundStyle(LineyTheme.secondaryText)
                            .textSelection(.enabled)
                    }

                    previewView(for: entry)

                    HStack {
                        Button {
                            store.openInFinder(path: entry.path)
                        } label: {
                            Label(localized("sheet.fileBrowser.reveal"), systemImage: "folder")
                        }
                        Button {
                            store.openWorkspaceFileInExternalEditor(entry.path)
                        } label: {
                            Label(localized("sheet.fileBrowser.openExternal"), systemImage: "arrow.up.forward.square")
                        }
                        Spacer()
                        if case .text = previewState {
                            Button {
                                editableContents = lastLoadedContents
                            } label: {
                                Label(localized("sheet.fileBrowser.revert"), systemImage: "arrow.counterclockwise")
                            }
                            .disabled(!hasUnsavedChanges)

                            Button {
                                store.saveWorkspaceFileBrowserText(contents: editableContents, to: entry.path)
                                lastLoadedContents = editableContents
                                previewState = .text(editableContents)
                            } label: {
                                Label(localized("common.save"), systemImage: "checkmark")
                            }
                            .disabled(!hasUnsavedChanges)
                        }
                    }
                } else {
                    Spacer()
                    ContentUnavailableView(
                        localized("sheet.fileBrowser.selectTitle"),
                        systemImage: "doc.text",
                        description: Text(localized("sheet.fileBrowser.selectDescription"))
                    )
                    Spacer()
                }
            }
            .padding(20)
            .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 920, minHeight: 620)
        .task {
            await loadFiles()
        }
        .onChange(of: filteredFiles.map(\.path)) { _, paths in
            guard !paths.isEmpty else {
                selectedFilePath = nil
                return
            }
            if let selectedFilePath, paths.contains(selectedFilePath) {
                return
            }
            self.selectedFilePath = paths[0]
        }
        .onChange(of: selectedFilePath) { _, newValue in
            guard let newValue else {
                previewState = .idle
                editableContents = ""
                lastLoadedContents = ""
                return
            }
            loadPreview(for: newValue)
        }
    }

    @ViewBuilder
    private func previewView(for entry: WorkspaceFileBrowserEntry) -> some View {
        switch previewState {
        case .idle:
            Color.clear
        case .loading:
            Spacer()
            ProgressView(localized("sheet.fileBrowser.loadingPreview"))
            Spacer()
        case .text:
            TextEditor(text: $editableContents)
                .font(.system(.body, design: .monospaced))
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LineyTheme.panelRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(LineyTheme.border, lineWidth: 1)
                )
        case .unsupported(let reason):
            unsupportedView(entry: entry, reason: reason)
        case .failed(let message):
            unsupportedView(entry: entry, reason: message)
        }
    }

    @ViewBuilder
    private func unsupportedView(entry: WorkspaceFileBrowserEntry, reason: String) -> some View {
        Spacer()
        ContentUnavailableView(
            localized("sheet.fileBrowser.unsupportedTitle"),
            systemImage: "doc.slash",
            description: Text(unsupportedMessage(for: entry, reason: reason))
        )
        Spacer()
    }

    private func unsupportedMessage(for entry: WorkspaceFileBrowserEntry, reason: String) -> String {
        switch reason {
        case "large":
            return localizedFormat("sheet.fileBrowser.unsupportedLargeFormat", entry.fileName)
        case "binary":
            return localizedFormat("sheet.fileBrowser.unsupportedBinaryFormat", entry.fileName)
        default:
            return reason
        }
    }

    private func loadFiles() async {
        isLoadingFiles = true
        let rootPath = request.rootPath
        do {
            let entries = try await Task.detached {
                try WorkspaceFileBrowserSupport.enumerateFiles(in: rootPath)
            }.value
            files = entries
            selectedFilePath = entries.first?.path
        } catch {
            files = []
            previewState = .failed(error.localizedDescription)
        }
        isLoadingFiles = false
    }

    private func loadPreview(for path: String) {
        previewState = .loading
        let targetPath = path
        Task {
            do {
                let preview = try await Task.detached {
                    try WorkspaceFileBrowserSupport.loadPreview(at: targetPath)
                }.value

                guard selectedFilePath == targetPath else { return }

                switch preview {
                case .text(let contents):
                    editableContents = contents
                    lastLoadedContents = contents
                    previewState = .text(contents)
                case .unsupported(let reason):
                    editableContents = ""
                    lastLoadedContents = ""
                    previewState = .unsupported(reason)
                }
            } catch {
                guard selectedFilePath == targetPath else { return }
                editableContents = ""
                lastLoadedContents = ""
                previewState = .failed(error.localizedDescription)
            }
        }
    }
}
