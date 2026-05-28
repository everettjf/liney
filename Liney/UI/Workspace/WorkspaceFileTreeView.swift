//
//  WorkspaceFileTreeView.swift
//  Liney
//
//  Author: everettjf
//

import AppKit
import SwiftUI

/// Directory tree column. Its root follows the focused terminal pane's current
/// working directory, so a `cd` in the terminal — or clicking a different pane —
/// automatically re-roots the tree. Clicking a Markdown or HTML file opens it in
/// the preview panel.
struct WorkspaceFileTreeView: View {
    @ObservedObject var workspace: WorkspaceModel
    @ObservedObject var sessionController: WorkspaceSessionController

    var body: some View {
        if let paneID = sessionController.focusedPaneID,
           let session = sessionController.session(for: paneID) {
            FileTreeFollowingSession(workspace: workspace, session: session, source: source)
        } else {
            FileTreeContent(workspace: workspace, rootPath: workspace.activeWorktreePath, source: source)
        }
    }

    /// Remote workspaces list their tree over SSH; everything else stays local.
    private var source: DirectoryTreeSource {
        if let target = workspace.sshTarget {
            return .remote(target)
        }
        return .local
    }
}

/// Where the file tree reads directory contents from: the local filesystem, or
/// a remote host over SSH (used by SSH terminal / remote workspaces).
enum DirectoryTreeSource: Equatable {
    case local
    case remote(SSHSessionConfiguration)

    var isRemote: Bool {
        if case .remote = self { return true }
        return false
    }
}

/// Observes the focused session so a reported working-directory change re-roots
/// the tree.
private struct FileTreeFollowingSession: View {
    @ObservedObject var workspace: WorkspaceModel
    @ObservedObject var session: ShellSession
    let source: DirectoryTreeSource

    var body: some View {
        FileTreeContent(workspace: workspace, rootPath: session.effectiveWorkingDirectory, source: source)
    }
}

/// Identity for a directory load: re-runs the loading task whenever the path,
/// manual refresh, or hidden-file toggle changes.
private struct FileTreeLoadKey: Hashable {
    let path: String
    let token: UUID
    let showsHidden: Bool
}

/// Outcome of a directory read: the listed entries, or a failure to list (so
/// the view can tell a genuinely empty folder apart from one it couldn't read —
/// e.g. a remote host the file tree's `BatchMode` SSH can't authenticate to).
private enum DirectoryLoadResult {
    case entries([DirectoryTreeEntry])
    case unavailable
}

/// Off-main directory read shared by the root and each row. Dispatches to the
/// local filesystem or to a remote host over SSH depending on `source`.
private func loadEntries(at path: String, source: DirectoryTreeSource, showsHidden: Bool) async -> DirectoryLoadResult {
    switch source {
    case .local:
        let url = URL(fileURLWithPath: path, isDirectory: true)
        let entries = await Task.detached(priority: .userInitiated) {
            DirectoryTreeLoader.entries(at: url, includesHidden: showsHidden)
        }.value
        return .entries(entries)
    case .remote(let config):
        do {
            let remote = try await RemoteDirectoryConnectionPool.shared.listEntries(
                config: config,
                path: path,
                includesHidden: showsHidden
            )
            return .entries(remote.map { entry in
                DirectoryTreeEntry(
                    url: URL(fileURLWithPath: entry.path, isDirectory: entry.isDirectory),
                    name: entry.name,
                    isDirectory: entry.isDirectory
                )
            })
        } catch {
            return .unavailable
        }
    }
}

private struct FileTreeContent: View {
    @EnvironmentObject private var store: WorkspaceStore
    @ObservedObject private var localization = LocalizationManager.shared
    @ObservedObject var workspace: WorkspaceModel
    let rootPath: String
    let source: DirectoryTreeSource

    @State private var selectedPath: String?
    @State private var showsHidden = false
    @State private var reloadToken = UUID()
    @State private var rootEntries: [DirectoryTreeEntry] = []
    @State private var isLoaded = false
    @State private var loadFailed = false

    private func localized(_ key: String) -> String { localization.string(key) }

    private var rootURL: URL {
        URL(fileURLWithPath: rootPath, isDirectory: true)
    }

    private var loadKey: FileTreeLoadKey {
        FileTreeLoadKey(path: rootPath, token: reloadToken, showsHidden: showsHidden)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(LineyTheme.border)

            ScrollView {
                if !rootEntries.isEmpty {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rootEntries) { entry in
                            FileTreeRow(
                                entry: entry,
                                depth: 0,
                                source: source,
                                showsHidden: showsHidden,
                                reloadToken: reloadToken,
                                selectedPath: $selectedPath,
                                onOpen: open(entry:),
                                onCommand: handle(command:for:)
                            )
                        }
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if isLoaded {
                    emptyMessage(localized(loadFailed ? "fileTree.unavailable" : "fileTree.empty"))
                } else {
                    emptyMessage(localized("fileTree.loading"))
                }
            }
            // Attaching the loader to the always-present ScrollView (not the
            // ForEach) guarantees it runs on first appear and whenever the
            // focused pane's directory, refresh, or hidden toggle changes.
            .task(id: loadKey) {
                isLoaded = false
                // Local readability can be checked up front; remote paths are
                // validated by the listing itself (a failure marks it unavailable).
                if !source.isRemote, !DirectoryTreeLoader.isReadableDirectory(rootPath) {
                    rootEntries = []
                    loadFailed = false
                    isLoaded = true
                    return
                }
                let result = await loadEntries(at: rootPath, source: source, showsHidden: showsHidden)
                guard !Task.isCancelled else { return }
                switch result {
                case .entries(let loaded):
                    rootEntries = loaded
                    loadFailed = false
                case .unavailable:
                    rootEntries = []
                    loadFailed = true
                }
                isLoaded = true
            }
        }
        .background(LineyTheme.sidebarBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(LineyTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(LineyTheme.localAccent)

            Text(rootURL.lastPathComponent.isEmpty ? rootPath : rootURL.lastPathComponent)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LineyTheme.tertiaryText)
                .lineLimit(1)
                .truncationMode(.head)
                .help(rootPath)

            Spacer(minLength: 2)

            headerButton("eye\(showsHidden ? ".fill" : "")", help: localized("fileTree.toggleHidden")) {
                showsHidden.toggle()
            }
            headerButton("arrow.clockwise", help: localized("fileTree.refresh")) {
                reloadToken = UUID()
            }
            headerButton("xmark", help: localized("fileTree.hide")) {
                workspace.isFileTreePresented = false
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(LineyTheme.paneHeaderBackground)
    }

    private func headerButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(LineyTheme.secondaryText)
        .help(help)
    }

    private func emptyMessage(_ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 20))
                .foregroundStyle(LineyTheme.mutedText)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(LineyTheme.mutedText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
    }

    // MARK: - Actions

    private func open(entry: DirectoryTreeEntry) {
        selectedPath = entry.url.path
        guard !entry.isDirectory else { return }
        // Remote files live on another host; opening/previewing them locally
        // isn't possible yet, so selecting is the only action.
        guard !source.isRemote else { return }
        if let content = WorkspacePreviewContent.makeFile(entry.url) {
            workspace.openPreview(content)
        } else {
            NSWorkspace.shared.open(entry.url)
        }
    }

    private func handle(command: FileTreeCommand, for entry: DirectoryTreeEntry) {
        switch command {
        case .reveal:
            NSWorkspace.shared.activateFileViewerSelecting([entry.url])
        case .openExternal:
            NSWorkspace.shared.open(entry.url)
        case .openInPreview:
            if let content = WorkspacePreviewContent.makeFile(entry.url) {
                workspace.openPreview(content)
            }
        case .copyPath:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.url.path, forType: .string)
        case .changeDirectory:
            changeDirectory(to: entry.url)
        }
    }

    private func changeDirectory(to url: URL) {
        let directory = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        guard let paneID = workspace.sessionController.focusedPaneID,
              let session = workspace.sessionController.session(for: paneID) else { return }
        let escaped = directory.path.replacingOccurrences(of: "'", with: "'\\''")
        session.sendShellCommand("cd '\(escaped)'")
    }
}

enum FileTreeCommand {
    case reveal
    case openExternal
    case openInPreview
    case copyPath
    case changeDirectory
}

private struct FileTreeRow: View {
    @ObservedObject private var localization = LocalizationManager.shared
    let entry: DirectoryTreeEntry
    let depth: Int
    let source: DirectoryTreeSource
    let showsHidden: Bool
    let reloadToken: UUID
    @Binding var selectedPath: String?
    let onOpen: (DirectoryTreeEntry) -> Void
    let onCommand: (FileTreeCommand, DirectoryTreeEntry) -> Void

    @State private var isExpanded = false
    @State private var isHovered = false
    @State private var children: [DirectoryTreeEntry] = []

    private func localized(_ key: String) -> String { localization.string(key) }

    private var isSelected: Bool { selectedPath == entry.url.path }

    private var childLoadKey: FileTreeLoadKey {
        FileTreeLoadKey(path: isExpanded ? entry.url.path : "", token: reloadToken, showsHidden: showsHidden)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row
            if entry.isDirectory, isExpanded {
                ForEach(children) { child in
                    FileTreeRow(
                        entry: child,
                        depth: depth + 1,
                        source: source,
                        showsHidden: showsHidden,
                        reloadToken: reloadToken,
                        selectedPath: $selectedPath,
                        onOpen: onOpen,
                        onCommand: onCommand
                    )
                }
            }
        }
        // Loads children when the row is expanded; re-runs on refresh / hidden
        // toggle. Attached to the always-present VStack so it fires reliably.
        .task(id: childLoadKey) {
            guard entry.isDirectory, isExpanded else { return }
            let result = await loadEntries(at: entry.url.path, source: source, showsHidden: showsHidden)
            guard !Task.isCancelled else { return }
            if case .entries(let loaded) = result {
                children = loaded
            } else {
                children = []
            }
        }
    }

    private var row: some View {
        HStack(spacing: 5) {
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(LineyTheme.mutedText)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 10)
                .opacity(entry.isDirectory ? 1 : 0)

            Image(systemName: entry.symbolName)
                .font(.system(size: 11))
                .foregroundStyle(iconColor)
                .frame(width: 15)

            Text(entry.name)
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? .white : LineyTheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .padding(.trailing, 8)
        .padding(.leading, CGFloat(depth) * 12 + 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { activate() }
        .onDrag { dragItemProvider() }
        .contextMenu { contextMenu }
    }

    /// Drag payload for dropping onto a terminal (à la VSCode). Local entries
    /// carry a file URL (so drag-to-Finder works); the terminal's drop handler
    /// backslash-escapes file-URL paths, so they insert unquoted. Remote entries
    /// have no local file URL, so the backslash-escaped remote path is provided
    /// as plain text, which the terminal inserts as-is.
    private func dragItemProvider() -> NSItemProvider {
        switch source {
        case .local:
            return NSItemProvider(object: entry.url as NSURL)
        case .remote:
            return NSItemProvider(object: entry.url.path.shellEscaped as NSString)
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        // Preview / Reveal / Open externally act on the local filesystem, so
        // they're omitted for remote entries; cd and Copy Path work for both.
        if entry.isPreviewable, !source.isRemote {
            Button(localized("fileTree.menu.openInPreview")) { onCommand(.openInPreview, entry) }
            Divider()
        }
        if entry.isDirectory {
            Button(localized("fileTree.menu.cdHere")) { onCommand(.changeDirectory, entry) }
        }
        if !source.isRemote {
            Button(localized("fileTree.menu.reveal")) { onCommand(.reveal, entry) }
            Button(localized("fileTree.menu.openExternal")) { onCommand(.openExternal, entry) }
        }
        Button(localized("fileTree.menu.copyPath")) { onCommand(.copyPath, entry) }
    }

    private func activate() {
        if entry.isDirectory {
            withAnimation(.easeInOut(duration: 0.12)) { isExpanded.toggle() }
            selectedPath = entry.url.path
        } else {
            onOpen(entry)
        }
    }

    private var iconColor: Color {
        if entry.isDirectory { return LineyTheme.localAccent }
        if entry.isPreviewable { return LineyTheme.accent }
        return LineyTheme.mutedText
    }

    private var rowBackground: Color {
        if isSelected { return LineyTheme.accentMuted.opacity(0.55) }
        if isHovered { return LineyTheme.subtleFill }
        return .clear
    }
}
