//
//  WorkspaceMetadataWatchService.swift
//  Liney
//
//  Author: everettjf
//

import Foundation
import Darwin

@MainActor
final class WorkspaceMetadataWatchService {
    static let shared = WorkspaceMetadataWatchService()

    private struct WatchHandle {
        let workspaceID: UUID
        let path: String
        let descriptor: Int32
        let source: DispatchSourceFileSystemObject
    }

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.liney.workspace-metadata-watch")
    /// Keyed by "<workspaceID>|<path>" so configure() can diff the target set
    /// against the current set and only open/close the descriptors that
    /// actually changed. Recreating DispatchSources on every git refresh was
    /// expensive enough to show up in CPU profiles.
    private var handles: [String: WatchHandle] = [:]
    private var pendingCallbacks: [UUID: DispatchWorkItem] = [:]
    private var lastCallbackTime: [UUID: CFAbsoluteTime] = [:]
    /// Minimum interval between callbacks for the same workspace, to prevent
    /// queue buildup during bulk file operations (e.g. git checkout).
    private let minCallbackInterval: CFAbsoluteTime = 1.0

    func configure(
        workspaces: [WorkspaceModel],
        isEnabled: Bool,
        onChange: @escaping @Sendable (UUID) -> Void
    ) {
        guard isEnabled else {
            stop()
            return
        }

        var targetKeys = Set<String>()
        var targetEntries: [(key: String, id: UUID, path: String)] = []
        for workspace in workspaces {
            let paths = Set(watchPaths(for: workspace))
            for path in paths {
                let key = Self.handleKey(id: workspace.id, path: path)
                targetKeys.insert(key)
                targetEntries.append((key, workspace.id, path))
            }
        }

        for (key, handle) in handles where !targetKeys.contains(key) {
            handle.source.cancel()
            handles.removeValue(forKey: key)
        }

        for entry in targetEntries where handles[entry.key] == nil {
            startWatching(path: entry.path, workspaceID: entry.id, key: entry.key, onChange: onChange)
        }

        let activeWorkspaceIDs = Set(targetEntries.map(\.id))
        for id in Array(pendingCallbacks.keys) where !activeWorkspaceIDs.contains(id) {
            pendingCallbacks[id]?.cancel()
            pendingCallbacks.removeValue(forKey: id)
            lastCallbackTime.removeValue(forKey: id)
        }
    }

    func stop() {
        for workItem in pendingCallbacks.values {
            workItem.cancel()
        }
        pendingCallbacks.removeAll()
        lastCallbackTime.removeAll()

        for handle in handles.values {
            handle.source.cancel()
        }
        handles.removeAll()
    }

    private static func handleKey(id: UUID, path: String) -> String {
        "\(id.uuidString)|\(path)"
    }

    private func startWatching(
        path: String,
        workspaceID: UUID,
        key: String,
        onChange: @escaping @Sendable (UUID) -> Void
    ) {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .attrib, .extend, .link, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleCallback(for: workspaceID, onChange: onChange)
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        handles[key] = WatchHandle(workspaceID: workspaceID, path: path, descriptor: descriptor, source: source)
    }

    private func scheduleCallback(
        for workspaceID: UUID,
        onChange: @escaping @Sendable (UUID) -> Void
    ) {
        pendingCallbacks[workspaceID]?.cancel()

        // Calculate delay: at least minCallbackInterval since the last actual callback
        let now = CFAbsoluteTimeGetCurrent()
        let lastTime = lastCallbackTime[workspaceID] ?? 0
        let elapsed = now - lastTime
        let delay = max(0.5, minCallbackInterval - elapsed)

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.lastCallbackTime[workspaceID] = CFAbsoluteTimeGetCurrent()
            }
            onChange(workspaceID)
        }
        pendingCallbacks[workspaceID] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func watchPaths(for workspace: WorkspaceModel) -> [String] {
        workspace.worktrees.flatMap { worktree -> [String] in
            guard let gitDirectory = resolveGitDirectory(for: worktree.path) else { return [] }
            return [
                gitDirectory,
                URL(fileURLWithPath: gitDirectory).appendingPathComponent("HEAD").path,
                URL(fileURLWithPath: gitDirectory).appendingPathComponent("index").path,
                URL(fileURLWithPath: gitDirectory).appendingPathComponent("FETCH_HEAD").path,
                URL(fileURLWithPath: gitDirectory).appendingPathComponent("refs").path,
                URL(fileURLWithPath: gitDirectory).appendingPathComponent("refs/heads").path,
                URL(fileURLWithPath: gitDirectory).appendingPathComponent("refs/remotes").path,
            ]
            .filter { fileManager.fileExists(atPath: $0) }
        }
    }

    private func resolveGitDirectory(for worktreePath: String) -> String? {
        let dotGitURL = URL(fileURLWithPath: worktreePath).appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: dotGitURL.path, isDirectory: &isDirectory) else {
            return nil
        }
        if isDirectory.boolValue {
            return dotGitURL.path
        }

        guard let contents = try? String(contentsOf: dotGitURL, encoding: .utf8) else {
            return nil
        }
        let prefix = "gitdir:"
        guard let line = contents.split(whereSeparator: \.isNewline).first,
              line.lowercased().hasPrefix(prefix) else {
            return nil
        }
        let rawPath = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedURL = URL(fileURLWithPath: rawPath, relativeTo: dotGitURL.deletingLastPathComponent())
        return resolvedURL.standardizedFileURL.path
    }
}
