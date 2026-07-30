//
//  DiffWindowState.swift
//  Liney
//
//  Author: everettjf
//

import Combine
import Foundation

struct DiffFileDocument: Sendable {
    let file: DiffChangedFile
    let unifiedPatch: String
}

/// A sibling worktree the current changes can be applied to.
struct WorktreeApplyTarget: Identifiable, Hashable {
    let path: String
    let displayName: String
    let branch: String?

    var id: String { path }
}

/// Outcome of the `git apply --check` dry-run shown before the user commits to
/// applying changes to another worktree.
struct WorktreeApplyPreview: Equatable {
    let target: WorktreeApplyTarget
    let fileCount: Int
    let appliesCleanly: Bool
    let detail: String
}

/// Final result of an apply attempt.
struct DiffApplyResult: Equatable {
    let success: Bool
    let message: String
}

/// Conflicts left in the target worktree after a 3-way apply, pending resolution.
struct WorktreeConflictState: Equatable {
    let target: WorktreeApplyTarget
    var files: [String]
}

/// Drives the "apply to another worktree" flow surfaced as a sheet.
enum DiffApplyPhase: Equatable {
    case idle
    case working
    case preview(WorktreeApplyPreview)
    case conflicts(WorktreeConflictState)
    case result(DiffApplyResult)
}

enum DiffDiagnostics {
    nonisolated static func log(_ message: String) {
#if DEBUG
        print("[Diff] \(message)")
#endif
    }

    nonisolated static func error(_ message: String) {
#if DEBUG
        print("[Diff][Error] \(message)")
#endif
    }

    nonisolated static func now() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    nonisolated static func elapsedMilliseconds(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    nonisolated static func formatMilliseconds(_ value: Double) -> String {
        String(format: "%.1fms", value)
    }

    nonisolated static func describeText(_ text: String) -> String {
        "\(text.utf8.count)B/\(lineCount(in: text)) lines"
    }

    nonisolated static func lineCount(in text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return text.split(separator: "\n", omittingEmptySubsequences: false).count
    }
}

@MainActor
final class DiffWindowState: ObservableObject {
    @Published var worktreePath: String?
    @Published var branchName: String = ""
    @Published var emptyStateMessage: String = "Working directory is clean."
    @Published var changedFiles: [DiffChangedFile] = []
    @Published var selectedFileID: String?
    @Published var document: DiffFileDocument?
    @Published var isLoadingFiles = false
    @Published var isLoadingDocument = false
    @Published var loadErrorMessage: String?
    @Published var isCommitting = false
    @Published var commitErrorMessage: String?

    /// Sibling worktrees the current changes can be applied to / compared against.
    @Published var availableTargets: [WorktreeApplyTarget] = []
    /// State of the "apply to another worktree" flow.
    @Published var applyPhase: DiffApplyPhase = .idle

    /// Parsed sections/hunks of the apply patch, for hunk-level cherry-pick.
    @Published var patchSections: [PatchFileSection] = []
    /// IDs of the hunks selected for the current apply. Defaults to every hunk.
    @Published var selectedHunkIDs: Set<String> = []

    /// When set, the window compares the base worktree against this target
    /// (A/B compare) instead of showing changes vs HEAD.
    @Published var compareTarget: WorktreeApplyTarget?

    private let gitRepositoryService = GitRepositoryService()
    private var documentCache: [String: DiffFileDocument] = [:]
    private var fileListTask: Task<Void, Never>?
    private var documentTask: Task<Void, Never>?
    private var targetsTask: Task<Void, Never>?
    private var applyTask: Task<Void, Never>?
    private var pendingTarget: WorktreeApplyTarget?
    // Resolved tree snapshots for the active compare (base vs target).
    private var compareBaseTree: String?
    private var compareTargetTree: String?

    func load(worktreePath: String?, branchName: String, emptyStateMessage: String) {
        DiffDiagnostics.log("Loading diff window state for branch \(branchName) at \(worktreePath ?? "<nil>")")
        self.worktreePath = worktreePath
        self.branchName = branchName
        self.emptyStateMessage = emptyStateMessage
        changedFiles = []
        selectedFileID = nil
        document = nil
        loadErrorMessage = nil
        documentCache = [:]
        availableTargets = []
        compareTarget = nil
        compareBaseTree = nil
        compareTargetTree = nil
        resetApplyFlow()
        fileListTask?.cancel()
        documentTask?.cancel()
        guard let worktreePath else {
            isLoadingFiles = false
            isLoadingDocument = false
            return
        }
        fileListTask = Task { await reloadFileList(for: worktreePath) }
        reloadTargets(for: worktreePath)
    }

    func refresh() {
        guard let worktreePath else { return }
        DiffDiagnostics.log("Refreshing diff file list for \(worktreePath)")
        documentCache = [:]
        fileListTask?.cancel()
        documentTask?.cancel()
        if compareTarget != nil {
            fileListTask = Task { await reloadCompareFileList() }
        } else {
            fileListTask = Task { await reloadFileList(for: worktreePath) }
        }
        reloadTargets(for: worktreePath)
    }

    /// Stages and commits every change in the current worktree, then reloads the
    /// (now empty) file list. Returns `true` on success. Surfaces failures via
    /// `commitErrorMessage` so the commit sheet can keep the message for a retry.
    @discardableResult
    func commitAllChanges(message: String) async -> Bool {
        guard let worktreePath else { return false }
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            commitErrorMessage = "Commit message cannot be empty."
            return false
        }

        isCommitting = true
        commitErrorMessage = nil
        defer { isCommitting = false }

        do {
            try await gitRepositoryService.commitAllChanges(in: worktreePath, message: trimmedMessage)
            DiffDiagnostics.log("Committed changes in \(worktreePath)")
            refresh()
            return true
        } catch {
            DiffDiagnostics.error("Commit failed for \(worktreePath): \(error.localizedDescription)")
            commitErrorMessage = error.localizedDescription.nonEmptyOrFallback("Unable to commit changes.")
            return false
        }
    }

    func updateDocumentSelection(for id: String?) {
        documentTask?.cancel()
        DiffDiagnostics.log("Selecting diff file id \(id ?? "<nil>")")

        guard let id,
              let worktreePath,
              let file = changedFiles.first(where: { $0.id == id }) else {
            DiffDiagnostics.log("Clearing diff document because selection is empty or missing")
            document = nil
            isLoadingDocument = false
            return
        }

        if let cached = documentCache[id] {
            DiffDiagnostics.log("Using cached diff document for \(file.displayPath)")
            document = cached
            isLoadingDocument = false
            return
        }

        let compareTrees: (base: String, target: String)?
        if let compareBaseTree, let compareTargetTree {
            compareTrees = (compareBaseTree, compareTargetTree)
        } else {
            compareTrees = nil
        }

        document = nil
        isLoadingDocument = true
        documentTask = Task {
            let start = DiffDiagnostics.now()
            DiffDiagnostics.log("Starting diff load for \(file.displayPath)")
            do {
                let loadedDocument = try await Task.detached(priority: .userInitiated) {
                    if let compareTrees {
                        return try await Self.loadCompareDocument(
                            for: file,
                            repoPath: worktreePath,
                            base: compareTrees.base,
                            target: compareTrees.target
                        )
                    }
                    return try await Self.loadDocument(for: file, worktreePath: worktreePath)
                }.value
                guard !Task.isCancelled else { return }
                documentCache[file.id] = loadedDocument
                document = loadedDocument
                isLoadingDocument = false
                DiffDiagnostics.log(
                    "Finished diff load for \(file.displayPath) in \(DiffDiagnostics.formatMilliseconds(DiffDiagnostics.elapsedMilliseconds(since: start))) [patchBytes=\(loadedDocument.unifiedPatch.utf8.count)]"
                )
            } catch {
                guard !Task.isCancelled else { return }
                DiffDiagnostics.error(
                    "Diff load failed for \(file.displayPath) after \(DiffDiagnostics.formatMilliseconds(DiffDiagnostics.elapsedMilliseconds(since: start))): \(error.localizedDescription)"
                )
                document = Self.makeDocument(
                    file: file,
                    unifiedPatch: error.localizedDescription.nonEmptyOrFallback("Unable to load diff.")
                )
                isLoadingDocument = false
            }
        }
    }

    // MARK: - Apply To Worktree

    private func reloadTargets(for worktreePath: String) {
        targetsTask?.cancel()
        targetsTask = Task {
            let worktrees = (try? await gitRepositoryService.listWorktrees(for: worktreePath)) ?? []
            guard !Task.isCancelled else { return }
            availableTargets = worktrees
                .filter { $0.path != worktreePath }
                .map { WorktreeApplyTarget(path: $0.path, displayName: $0.displayName, branch: $0.branch) }
        }
    }

    /// Opens the apply flow targeting `target`. Builds the full patch of the base
    /// worktree's changes, parses it into hunks (all selected by default), then
    /// dry-runs the result.
    func beginApply(to target: WorktreeApplyTarget) {
        guard let worktreePath else { return }
        guard !changedFiles.isEmpty else {
            applyPhase = .result(DiffApplyResult(success: false, message: "There are no changes to apply."))
            return
        }
        pendingTarget = target
        applyTask?.cancel()
        applyPhase = .working
        applyTask = Task {
            do {
                let patch = try await gitRepositoryService.workingTreePatch(for: worktreePath)
                guard !Task.isCancelled else { return }
                let sections = UnifiedPatch.parse(patch)
                patchSections = sections
                selectedHunkIDs = Set(sections.flatMap { $0.hunks.map(\.id) })
                await runPrecheck()
            } catch {
                guard !Task.isCancelled else { return }
                applyPhase = .result(DiffApplyResult(success: false, message: error.localizedDescription))
            }
        }
    }

    /// Toggles a single hunk and re-runs the precheck.
    func toggleHunk(_ id: String) {
        if selectedHunkIDs.contains(id) {
            selectedHunkIDs.remove(id)
        } else {
            selectedHunkIDs.insert(id)
        }
        rerunPrecheckIfPreviewing()
    }

    /// Toggles every hunk of a file section at once and re-runs the precheck.
    func toggleSection(_ section: PatchFileSection) {
        let ids = section.hunks.map(\.id)
        if ids.allSatisfy({ selectedHunkIDs.contains($0) }) {
            ids.forEach { selectedHunkIDs.remove($0) }
        } else {
            ids.forEach { selectedHunkIDs.insert($0) }
        }
        rerunPrecheckIfPreviewing()
    }

    func isSectionFullySelected(_ section: PatchFileSection) -> Bool {
        !section.hunks.isEmpty && section.hunks.allSatisfy { selectedHunkIDs.contains($0.id) }
    }

    private func rerunPrecheckIfPreviewing() {
        switch applyPhase {
        case .preview, .working:
            applyTask?.cancel()
            applyTask = Task { await runPrecheck() }
        default:
            break
        }
    }

    /// Reassembles the selected hunks into a patch and dry-runs it against the
    /// pending target, moving the flow into a preview the user can confirm.
    private func runPrecheck() async {
        guard let target = pendingTarget else { return }
        applyPhase = .working

        let patch = UnifiedPatch.reassemble(selectedHunkIDs: selectedHunkIDs, from: patchSections)
        let fileCount = patchSections.filter { section in
            section.hunks.contains { selectedHunkIDs.contains($0.id) }
        }.count

        do {
            guard let patch = patch.nilIfEmpty else {
                applyPhase = .preview(
                    WorktreeApplyPreview(target: target, fileCount: 0, appliesCleanly: false, detail: "Select at least one hunk to apply.")
                )
                return
            }
            let precheck = try await gitRepositoryService.precheckApplyPatch(patch, to: target.path)
            guard !Task.isCancelled else { return }
            applyPhase = .preview(
                WorktreeApplyPreview(
                    target: target,
                    fileCount: fileCount,
                    appliesCleanly: precheck.appliesCleanly,
                    detail: precheck.message
                )
            )
        } catch {
            guard !Task.isCancelled else { return }
            applyPhase = .result(DiffApplyResult(success: false, message: error.localizedDescription))
        }
    }

    /// Applies the selected hunks to the pending target. Pass `threeWay` to fall
    /// back to a 3-way merge for patches that don't apply cleanly; if that leaves
    /// conflicts, the flow moves to interactive resolution.
    func confirmApply(threeWay: Bool) {
        guard let target = pendingTarget else { return }
        let patch = UnifiedPatch.reassemble(selectedHunkIDs: selectedHunkIDs, from: patchSections)
        guard let patch = patch.nilIfEmpty else { return }
        let fileCount = patchSections.filter { section in
            section.hunks.contains { selectedHunkIDs.contains($0.id) }
        }.count

        applyTask?.cancel()
        applyPhase = .working
        applyTask = Task {
            do {
                let outcome = try await gitRepositoryService.applyPatch(patch, to: target.path, threeWay: threeWay)
                guard !Task.isCancelled else { return }
                if outcome.hasConflicts {
                    applyPhase = .conflicts(WorktreeConflictState(target: target, files: outcome.conflictedFiles))
                } else {
                    applyPhase = .result(
                        DiffApplyResult(success: true, message: "Applied \(fileCount) file(s) to \(target.displayName).")
                    )
                    pendingTarget = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                applyPhase = .result(DiffApplyResult(success: false, message: error.localizedDescription))
            }
        }
    }

    /// Resolves one conflicted file by taking the incoming (theirs) or target
    /// (ours) side. When the last conflict is resolved the flow reports success.
    func resolveConflict(file: String, useTheirs: Bool) {
        guard case .conflicts(var conflictState) = applyPhase else { return }
        let target = conflictState.target
        applyTask?.cancel()
        applyTask = Task {
            do {
                try await gitRepositoryService.resolveConflict(file: file, in: target.path, useTheirs: useTheirs)
                guard !Task.isCancelled else { return }
                conflictState.files.removeAll { $0 == file }
                if conflictState.files.isEmpty {
                    applyPhase = .result(
                        DiffApplyResult(success: true, message: "Resolved all conflicts in \(target.displayName).")
                    )
                    pendingTarget = nil
                } else {
                    applyPhase = .conflicts(conflictState)
                }
            } catch {
                guard !Task.isCancelled else { return }
                applyPhase = .result(DiffApplyResult(success: false, message: error.localizedDescription))
            }
        }
    }

    func cancelApply() {
        resetApplyFlow()
    }

    private func resetApplyFlow() {
        applyTask?.cancel()
        applyTask = nil
        pendingTarget = nil
        patchSections = []
        selectedHunkIDs = []
        applyPhase = .idle
    }

    // MARK: - Compare Worktrees (A/B)

    /// Switches the window into A/B compare mode against `target`.
    func startCompare(with target: WorktreeApplyTarget) {
        guard worktreePath != nil else { return }
        resetApplyFlow()
        compareTarget = target
        compareBaseTree = nil
        compareTargetTree = nil
        documentCache = [:]
        changedFiles = []
        selectedFileID = nil
        document = nil
        fileListTask?.cancel()
        documentTask?.cancel()
        fileListTask = Task { await reloadCompareFileList() }
    }

    /// Leaves compare mode and returns to showing changes vs HEAD.
    func endCompare() {
        guard let worktreePath else { return }
        compareTarget = nil
        compareBaseTree = nil
        compareTargetTree = nil
        documentCache = [:]
        changedFiles = []
        selectedFileID = nil
        document = nil
        fileListTask?.cancel()
        documentTask?.cancel()
        fileListTask = Task { await reloadFileList(for: worktreePath) }
    }

    private func reloadCompareFileList() async {
        guard let worktreePath, let compareTarget else { return }
        isLoadingFiles = true
        loadErrorMessage = nil
        do {
            let base = try await gitRepositoryService.worktreeContentTree(for: worktreePath)
            let target = try await gitRepositoryService.worktreeContentTree(for: compareTarget.path)
            guard !Task.isCancelled else { return }
            compareBaseTree = base
            compareTargetTree = target

            let nameStatus = try await gitRepositoryService.diffNameStatusBetweenCommits(
                for: worktreePath,
                fromCommit: base,
                toCommit: target
            )
            let files = DiffChangedFile.parseNameStatus(nameStatus).sorted {
                $0.displayPath.localizedStandardCompare($1.displayPath) == .orderedAscending
            }
            guard !Task.isCancelled else { return }
            changedFiles = files
            isLoadingFiles = false

            let nextSelectionID = files.first?.id
            selectedFileID = nextSelectionID
            updateDocumentSelection(for: nextSelectionID)
        } catch {
            guard !Task.isCancelled else { return }
            changedFiles = []
            document = nil
            selectedFileID = nil
            isLoadingFiles = false
            isLoadingDocument = false
            loadErrorMessage = error.localizedDescription.nonEmptyOrFallback("Unable to load comparison.")
        }
    }

    private func reloadFileList(for worktreePath: String) async {
        let start = DiffDiagnostics.now()
        DiffDiagnostics.log("Loading changed files for \(worktreePath)")
        isLoadingFiles = true
        loadErrorMessage = nil

        do {
            async let trackedOutput = gitRepositoryService.diffNameStatus(for: worktreePath)
            async let untrackedPaths = gitRepositoryService.untrackedFilePaths(for: worktreePath)

            let trackedFiles = DiffChangedFile.parseNameStatus(try await trackedOutput)
            let untrackedFiles = try await untrackedPaths.map {
                DiffChangedFile(status: .added, oldPath: nil, newPath: $0)
            }

            let allFiles = (trackedFiles + untrackedFiles).sorted {
                $0.displayPath.localizedStandardCompare($1.displayPath) == .orderedAscending
            }

            guard !Task.isCancelled else { return }

            changedFiles = allFiles
            isLoadingFiles = false
            DiffDiagnostics.log(
                "Loaded \(allFiles.count) changed files in \(DiffDiagnostics.formatMilliseconds(DiffDiagnostics.elapsedMilliseconds(since: start)))"
            )

            if let selectedFileID,
               allFiles.contains(where: { $0.id == selectedFileID }) {
                updateDocumentSelection(for: selectedFileID)
            } else {
                let nextSelectionID = allFiles.first?.id
                selectedFileID = nextSelectionID
                updateDocumentSelection(for: nextSelectionID)
            }
        } catch {
            guard !Task.isCancelled else { return }
            DiffDiagnostics.error(
                "Loading changed files failed after \(DiffDiagnostics.formatMilliseconds(DiffDiagnostics.elapsedMilliseconds(since: start))): \(error.localizedDescription)"
            )
            changedFiles = []
            document = nil
            selectedFileID = nil
            isLoadingFiles = false
            isLoadingDocument = false
            loadErrorMessage = error.localizedDescription.nonEmptyOrFallback("Unable to load diff.")
        }
    }

    nonisolated private static let maxPatchBytes = 1_000_000

    /// Loads a per-file diff document for A/B compare mode, diffing the two
    /// resolved tree snapshots.
    nonisolated private static func loadCompareDocument(
        for file: DiffChangedFile,
        repoPath: String,
        base: String,
        target: String
    ) async throws -> DiffFileDocument {
        let gitRepositoryService = GitRepositoryService()
        let diffPath = file.newPath ?? file.oldPath ?? file.displayPath
        let patch = try await gitRepositoryService.diffPatchBetweenCommits(
            for: repoPath,
            filePath: diffPath,
            fromCommit: base,
            toCommit: target
        )
        let unifiedPatch = patch.nilIfEmpty ?? "No unified patch available for \(file.displayPath)."
        if unifiedPatch.utf8.count > maxPatchBytes {
            return makeDocument(file: file, unifiedPatch: truncatePatch(unifiedPatch, maxBytes: maxPatchBytes))
        }
        return makeDocument(file: file, unifiedPatch: unifiedPatch)
    }

    nonisolated private static func loadDocument(for file: DiffChangedFile, worktreePath: String) async throws -> DiffFileDocument {
        let start = DiffDiagnostics.now()
        let unifiedPatch = try await loadUnifiedPatch(for: file, worktreePath: worktreePath)
        let patchSize = unifiedPatch.utf8.count
        DiffDiagnostics.log(
            "Completed document assembly for \(file.displayPath) in \(DiffDiagnostics.formatMilliseconds(DiffDiagnostics.elapsedMilliseconds(since: start))) [patch=\(patchSize)B]"
        )

        if patchSize > maxPatchBytes {
            DiffDiagnostics.log("Patch too large for \(file.displayPath): \(patchSize)B exceeds limit \(maxPatchBytes)B")
            let truncatedPatch = truncatePatch(unifiedPatch, maxBytes: maxPatchBytes)
            return makeDocument(file: file, unifiedPatch: truncatedPatch)
        }

        return makeDocument(file: file, unifiedPatch: unifiedPatch)
    }

    nonisolated private static func loadUnifiedPatch(
        for file: DiffChangedFile,
        worktreePath: String
    ) async throws -> String {
        let gitRepositoryService = GitRepositoryService()
        if file.status == .added, file.oldPath == nil {
            DiffDiagnostics.log("Using synthetic patch for added file \(file.displayPath)")
            let newContents = Self.readFile(at: URL(fileURLWithPath: worktreePath).appendingPathComponent(file.displayPath))
            return Self.syntheticPatch(for: file, oldContents: "", newContents: newContents)
        }

        let diffPath = file.newPath ?? file.oldPath ?? file.displayPath
        let start = DiffDiagnostics.now()
        DiffDiagnostics.log("Loading git patch for \(diffPath)")
        let patch = try await gitRepositoryService.diffPatch(for: worktreePath, filePath: diffPath)
        DiffDiagnostics.log(
            "Loaded git patch for \(diffPath) in \(DiffDiagnostics.formatMilliseconds(DiffDiagnostics.elapsedMilliseconds(since: start))) [\(patch.utf8.count)B]"
        )
        if let patch = patch.nilIfEmpty {
            return patch
        }
        if file.status == .deleted {
            DiffDiagnostics.log("Using synthetic patch for deleted file \(file.displayPath)")
            let oldContents = try await gitRepositoryService.showFileAtHEAD(file.oldPath ?? file.displayPath, in: worktreePath) ?? ""
            return Self.syntheticPatch(for: file, oldContents: oldContents, newContents: "")
        }
        return "No unified patch available for \(file.displayPath)."
    }

    nonisolated static func makeDocument(
        file: DiffChangedFile,
        unifiedPatch: String
    ) -> DiffFileDocument {
        return DiffFileDocument(
            file: file,
            unifiedPatch: unifiedPatch
        )
    }

    nonisolated private static let maxFileReadBytes = 1_000_000

    nonisolated private static func readFile(at url: URL) -> String {
        let start = DiffDiagnostics.now()
        guard let data = try? Data(contentsOf: url) else {
            DiffDiagnostics.error("Reading file failed for \(url.path)")
            return ""
        }
        if data.contains(0) {
            DiffDiagnostics.log(
                "Read binary file \(url.path) in \(DiffDiagnostics.formatMilliseconds(DiffDiagnostics.elapsedMilliseconds(since: start))) [\(data.count)B]"
            )
            return "<<Binary file>>"
        }
        if data.count > maxFileReadBytes {
            DiffDiagnostics.log(
                "File too large for inline diff \(url.path) [\(data.count)B exceeds \(maxFileReadBytes)B limit]"
            )
            let truncatedData = data.prefix(maxFileReadBytes)
            let partial = String(decoding: truncatedData, as: UTF8.self)
            let totalLines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false).count
            let keptLines = DiffDiagnostics.lineCount(in: partial)
            return partial + "\n\n… \(totalLines - keptLines) additional lines omitted (file too large, \(data.count / 1024)KB)"
        }
        if let string = String(data: data, encoding: .utf8) {
            DiffDiagnostics.log(
                "Read file \(url.path) in \(DiffDiagnostics.formatMilliseconds(DiffDiagnostics.elapsedMilliseconds(since: start))) [\(data.count)B/\(DiffDiagnostics.lineCount(in: string)) lines]"
            )
            return string
        }
        let string = String(decoding: data, as: UTF8.self)
        DiffDiagnostics.log(
            "Read non-UTF8 file \(url.path) in \(DiffDiagnostics.formatMilliseconds(DiffDiagnostics.elapsedMilliseconds(since: start))) [\(data.count)B/\(DiffDiagnostics.lineCount(in: string)) lines]"
        )
        return string
    }

    nonisolated private static func syntheticPatch(
        for file: DiffChangedFile,
        oldContents: String,
        newContents: String
    ) -> String {
        let path = file.displayPath
        switch file.status {
        case .added:
            return """
            diff --git a/\(path) b/\(path)
            --- /dev/null
            +++ b/\(path)
            \(patchHunk(oldPrefixCount: 0, newPrefixCount: lineCount(in: newContents), contents: newContents, prefix: "+"))
            """
        case .deleted:
            return """
            diff --git a/\(path) b/\(path)
            --- a/\(path)
            +++ /dev/null
            \(patchHunk(oldPrefixCount: lineCount(in: oldContents), newPrefixCount: 0, contents: oldContents, prefix: "-"))
            """
        default:
            return "No unified patch available for \(path)."
        }
    }

    nonisolated private static func patchHunk(
        oldPrefixCount: Int,
        newPrefixCount: Int,
        contents: String,
        prefix: Character
    ) -> String {
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
        let body = lines.map { "\(prefix)\($0)" }.joined(separator: "\n")
        let oldStart = oldPrefixCount == 0 ? 0 : 1
        let newStart = newPrefixCount == 0 ? 0 : 1
        return "@@ -\(oldStart),\(oldPrefixCount) +\(newStart),\(newPrefixCount) @@\n\(body)"
    }

    nonisolated private static func truncatePatch(_ patch: String, maxBytes: Int) -> String {
        let lines = patch.components(separatedBy: "\n")
        var result: [String] = []
        var currentBytes = 0

        for line in lines {
            let lineBytes = line.utf8.count + 1
            if currentBytes + lineBytes > maxBytes {
                break
            }
            result.append(line)
            currentBytes += lineBytes
        }

        let totalLines = DiffDiagnostics.lineCount(in: patch)
        let keptLines = result.count
        let omitted = totalLines - keptLines
        if omitted > 0 {
            result.append(" ")
            result.append(" … \(omitted) additional lines omitted (file too large)")
        }

        return result.joined(separator: "\n")
    }

    nonisolated private static func lineCount(in text: String) -> Int {
        DiffDiagnostics.lineCount(in: text)
    }
}
