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
    private var handles: [WatchHandle] = []
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
        stop()
        guard isEnabled else { return }

        for workspace in workspaces {
            let paths = watchPaths(for: workspace)
            for path in Set(paths) {
                startWatching(path: path, workspaceID: workspace.id, onChange: onChange)
            }
        }
    }

    func stop() {
        for workItem in pendingCallbacks.values {
            workItem.cancel()
        }
        pendingCallbacks.removeAll()
        lastCallbackTime.removeAll()

        for handle in handles {
            handle.source.cancel()
        }
        handles.removeAll()
    }

    private func startWatching(
        path: String,
        workspaceID: UUID,
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
        handles.append(WatchHandle(workspaceID: workspaceID, path: path, descriptor: descriptor, source: source))
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
