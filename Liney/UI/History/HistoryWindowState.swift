//
//  HistoryWindowState.swift
//  Liney
//
//  Author: everettjf
//

import Combine
import Foundation

enum HistoryViewMode: Equatable {
    case commitHistory
    case fileHistory(path: String)
    case blame(path: String, commit: String)
    case rangeComparison(from: String, to: String)
}

@MainActor
final class HistoryWindowState: ObservableObject {
    @Published var worktreePath: String?
    @Published var branchName: String = ""
    @Published var emptyStateMessage: String = "No commit history."

    // View mode
    @Published var viewMode: HistoryViewMode = .commitHistory

    // Commit list
    @Published var commits: [GitHistoryCommit] = []
    @Published var selectedCommitID: String?
    @Published var isLoadingCommits = false
    @Published var hasMoreCommits = true

    // Search
    @Published var searchQuery: String = ""

    // Branch switching
    @Published var branches: [String] = []
    @Published var selectedBranch: String?

    // Range comparison
    @Published var rangeStartCommitID: String?

    // Changed files for selected commit
    @Published var changedFiles: [DiffChangedFile] = []
    @Published var selectedFileID: String?
    @Published var isLoadingFiles = false

    // Diff document for selected file
    @Published var document: DiffFileDocument?
    @Published var isLoadingDocument = false

    // Blame
    @Published var blameLines: [GitBlameLine] = []
    @Published var isLoadingBlame = false

    @Published var loadErrorMessage: String?

    private let gitRepositoryService = GitRepositoryService()
    private var documentCache: [String: DiffFileDocument] = [:]
    private var commitListTask: Task<Void, Never>?
    private var numstatTask: Task<Void, Never>?
    private var fileListTask: Task<Void, Never>?
    private var documentTask: Task<Void, Never>?
    private var blameTask: Task<Void, Never>?
    private var branchTask: Task<Void, Never>?

    private static let pageSize = 100

    var filteredCommits: [GitHistoryCommit] {
        guard !searchQuery.isEmpty else { return commits }
        return commits.filter { $0.matches(query: searchQuery) }
    }

    func load(worktreePath: String?, branchName: String, emptyStateMessage: String) {
        DiffDiagnostics.log("Loading history window state for branch \(branchName) at \(worktreePath ?? "<nil>")")
        self.worktreePath = worktreePath
        self.branchName = branchName
        self.emptyStateMessage = emptyStateMessage
        viewMode = .commitHistory
        commits = []
        selectedCommitID = nil
        changedFiles = []
        selectedFileID = nil
        document = nil
        loadErrorMessage = nil
        documentCache = [:]
        searchQuery = ""
        rangeStartCommitID = nil
        blameLines = []
        hasMoreCommits = true
        selectedBranch = nil
        cancelAll()
        guard let worktreePath else {
            isLoadingCommits = false
            isLoadingFiles = false
            isLoadingDocument = false
            return
        }
        commitListTask = Task { await reloadCommitList(for: worktreePath, skip: 0) }
        branchTask = Task { await loadBranches(for: worktreePath) }
    }

    func refresh() {
        guard let worktreePath else { return }
        DiffDiagnostics.log("Refreshing history for \(worktreePath)")
        documentCache = [:]
        hasMoreCommits = true
        cancelAll()

        switch viewMode {
        case .commitHistory:
            commitListTask = Task { await reloadCommitList(for: worktreePath, skip: 0) }
        case .fileHistory(let path):
            commitListTask = Task { await reloadFileHistory(for: worktreePath, filePath: path) }
        case .blame(let path, let commit):
            blameTask = Task { await loadBlame(for: worktreePath, filePath: path, commit: commit) }
        case .rangeComparison(let from, let to):
            fileListTask = Task { await reloadRangeFileList(for: worktreePath, fromCommit: from, toCommit: to) }
        }
    }

    // MARK: - Pagination

    func loadMoreCommitsIfNeeded(currentCommitID: String) {
        guard hasMoreCommits, !isLoadingCommits else { return }
        guard let worktreePath else { return }
        // Trigger load more when the user scrolls near the last commit
        let threshold = max(0, commits.count - 5)
        guard let index = commits.firstIndex(where: { $0.id == currentCommitID }),
              index >= threshold else { return }

        DiffDiagnostics.log("Loading more commits (skip=\(commits.count))")
        commitListTask = Task { await reloadCommitList(for: worktreePath, skip: commits.count, append: true) }
    }

    // MARK: - Branch Switching

    func switchBranch(_ branch: String?) {
        guard let worktreePath else { return }
        selectedBranch = branch
        commits = []
        selectedCommitID = nil
        changedFiles = []
        selectedFileID = nil
        document = nil
        documentCache = [:]
        hasMoreCommits = true
        viewMode = .commitHistory
        cancelAll()
        commitListTask = Task { await reloadCommitList(for: worktreePath, skip: 0) }
    }

    // MARK: - Range Comparison

    func startRangeComparison(fromCommitID: String) {
        rangeStartCommitID = fromCommitID
    }

    func completeRangeComparison(toCommitID: String) {
        guard let from = rangeStartCommitID, let worktreePath else { return }
        rangeStartCommitID = nil
        viewMode = .rangeComparison(from: from, to: toCommitID)
        changedFiles = []
        selectedFileID = nil
        document = nil
        documentCache = [:]
        cancelAll()
        fileListTask = Task { await reloadRangeFileList(for: worktreePath, fromCommit: from, toCommit: toCommitID) }
    }

    func exitRangeComparison() {
        rangeStartCommitID = nil
        if case .rangeComparison = viewMode {
            viewMode = .commitHistory
            changedFiles = []
            selectedFileID = nil
            document = nil
            if let selectedCommitID {
                updateCommitSelection(for: selectedCommitID)
            }
        }
    }

    // MARK: - File History

    func showFileHistory(filePath: String) {
        guard let worktreePath else { return }
        viewMode = .fileHistory(path: filePath)
        commits = []
        selectedCommitID = nil
        changedFiles = []
        selectedFileID = nil
        document = nil
        documentCache = [:]
        blameLines = []
        cancelAll()
        commitListTask = Task { await reloadFileHistory(for: worktreePath, filePath: filePath) }
    }

    func exitFileHistory() {
        guard let worktreePath else { return }
        viewMode = .commitHistory
        commits = []
        selectedCommitID = nil
        changedFiles = []
        selectedFileID = nil
        document = nil
        documentCache = [:]
        hasMoreCommits = true
        cancelAll()
        commitListTask = Task { await reloadCommitList(for: worktreePath, skip: 0) }
    }

    // MARK: - Blame

    func showBlame(filePath: String, commit: String) {
        guard let worktreePath else { return }
        viewMode = .blame(path: filePath, commit: commit)
        blameLines = []
        cancelAll()
        blameTask = Task { await loadBlame(for: worktreePath, filePath: filePath, commit: commit) }
    }

    func exitBlame() {
        viewMode = .commitHistory
        blameLines = []
        blameTask?.cancel()
        if let selectedCommitID {
            updateCommitSelection(for: selectedCommitID)
        }
    }

    // MARK: - Commit Selection

    func updateCommitSelection(for id: String?) {
        fileListTask?.cancel()
        documentTask?.cancel()
        DiffDiagnostics.log("Selecting history commit id \(id ?? "<nil>")")

        guard let id,
              let worktreePath,
              let commit = commits.first(where: { $0.id == id }) else {
            changedFiles = []
            selectedFileID = nil
            document = nil
            isLoadingFiles = false
            isLoadingDocument = false
            return
        }

        // Handle range comparison mode
        if rangeStartCommitID != nil {
            completeRangeComparison(toCommitID: id)
            return
        }

        changedFiles = []
        selectedFileID = nil
        document = nil
        documentCache = [:]
        isLoadingFiles = true
        isLoadingDocument = false
        fileListTask = Task { await reloadFileList(for: worktreePath, commit: commit) }
    }

    // MARK: - File Selection

    func updateDocumentSelection(for id: String?) {
        documentTask?.cancel()
        DiffDiagnostics.log("Selecting history file id \(id ?? "<nil>")")

        guard let id,
              let worktreePath else {
            document = nil
            isLoadingDocument = false
            return
        }

        // Determine commit range based on view mode
        let fromCommit: String
        let toCommit: String
        switch viewMode {
        case .rangeComparison(let from, let to):
            fromCommit = from
            toCommit = to
        default:
            guard let selectedCommitID,
                  let commit = commits.first(where: { $0.id == selectedCommitID }) else {
                document = nil
                isLoadingDocument = false
                return
            }
            fromCommit = "\(commit.hash)~1"
            toCommit = commit.hash
        }

        guard let file = changedFiles.first(where: { $0.id == id }) else {
            document = nil
            isLoadingDocument = false
            return
        }

        let cacheKey = "\(fromCommit)..\(toCommit):\(id)"
        if let cached = documentCache[cacheKey] {
            DiffDiagnostics.log("Using cached history document for \(file.displayPath)")
            document = cached
            isLoadingDocument = false
            return
        }

        document = nil
        isLoadingDocument = true
        documentTask = Task {
            let start = DiffDiagnostics.now()
            do {
                let loadedDocument = try await Task.detached(priority: .userInitiated) {
                    try await Self.loadHistoryDocument(
                        for: file,
                        worktreePath: worktreePath,
                        fromCommit: fromCommit,
                        toCommit: toCommit
                    )
                }.value
                guard !Task.isCancelled else { return }
                documentCache[cacheKey] = loadedDocument
                document = loadedDocument
                isLoadingDocument = false
                DiffDiagnostics.log(
                    "Finished history diff load for \(file.displayPath) in \(DiffDiagnostics.formatMilliseconds(DiffDiagnostics.elapsedMilliseconds(since: start)))"
                )
            } catch {
                guard !Task.isCancelled else { return }
                DiffDiagnostics.error("History diff load failed for \(file.displayPath): \(error.localizedDescription)")
                document = DiffWindowState.makeDocument(
                    file: file,
                    unifiedPatch: error.localizedDescription.nonEmptyOrFallback("Unable to load diff.")
                )
                isLoadingDocument = false
            }
        }
    }

    // MARK: - Private Helpers

    private func cancelAll() {
        commitListTask?.cancel()
        numstatTask?.cancel()
        fileListTask?.cancel()
        documentTask?.cancel()
        blameTask?.cancel()
    }

    private func reloadCommitList(for worktreePath: String, skip: Int, append: Bool = false) async {
        let start = DiffDiagnostics.now()
        DiffDiagnostics.log("Loading commit history for \(worktreePath) (skip=\(skip), branch=\(selectedBranch ?? "current"))")
        isLoadingCommits = true
        if !append { loadErrorMessage = nil }

        do {
            // Load commit list first — show it immediately without waiting for numstat
            let logOutput = try await gitRepositoryService.commitLog(
                for: worktreePath,
                maxCount: Self.pageSize,
                branch: selectedBranch,
                skip: skip
            )

            guard !Task.isCancelled else { return }

            let parsed = GitHistoryCommit.parseLog(logOutput)

            if append {
                commits.append(contentsOf: parsed)
            } else {
                commits = parsed
            }
            hasMoreCommits = parsed.count >= Self.pageSize
            isLoadingCommits = false
            DiffDiagnostics.log(
                "Loaded \(parsed.count) commits in \(DiffDiagnostics.formatMilliseconds(DiffDiagnostics.elapsedMilliseconds(since: start)))"
            )

            if !append, let first = parsed.first {
                selectedCommitID = first.id
                updateCommitSelection(for: first.id)
            }

            // Load numstat in the background — enrich commits when ready, don't block UI
            numstatTask?.cancel()
            let currentBranch = selectedBranch
            numstatTask = Task {
                await self.loadNumstatInBackground(
                    for: worktreePath,
                    skip: skip,
                    branch: currentBranch,
                    commitHashes: Set(parsed.map(\.hash))
                )
            }
        } catch {
            guard !Task.isCancelled else { return }
            DiffDiagnostics.error("Loading commit history failed: \(error.localizedDescription)")
            if !append { commits = [] }
            isLoadingCommits = false
            hasMoreCommits = false
            loadErrorMessage = error.localizedDescription.nonEmptyOrFallback("Unable to load commit history.")
        }
    }

    /// Loads numstat in background and merges stats into existing commits without blocking the UI.
    private func loadNumstatInBackground(for worktreePath: String, skip: Int, branch: String?, commitHashes: Set<String>) async {
        let start = DiffDiagnostics.now()
        do {
            let numstatOutput = try await gitRepositoryService.commitLogNumstat(
                for: worktreePath,
                maxCount: Self.pageSize,
                branch: branch,
                skip: skip
            )
            guard !Task.isCancelled else { return }

            // Merge stats into existing commits
            let enriched = GitHistoryCommit.enrichWithStats(commits, numstatOutput: numstatOutput)
            commits = enriched
            DiffDiagnostics.log(
                "Enriched commits with numstat in \(DiffDiagnostics.formatMilliseconds(DiffDiagnostics.elapsedMilliseconds(since: start)))"
            )
        } catch {
            // numstat failure is non-critical — commits still show without stats
            guard !Task.isCancelled else { return }
            DiffDiagnostics.error("Numstat load failed (non-critical): \(error.localizedDescription)")
        }
    }

    private func reloadFileHistory(for worktreePath: String, filePath: String) async {
        let start = DiffDiagnostics.now()
        DiffDiagnostics.log("Loading file history for \(filePath)")
        isLoadingCommits = true
        loadErrorMessage = nil

        do {
            let output = try await gitRepositoryService.fileCommitLog(
                for: worktreePath,
                filePath: filePath
            )
            guard !Task.isCancelled else { return }
            let parsed = GitHistoryCommit.parseLog(output)
            commits = parsed
            hasMoreCommits = false  // file history loads all at once
            isLoadingCommits = false
            DiffDiagnostics.log("Loaded \(parsed.count) commits for file \(filePath) in \(DiffDiagnostics.formatMilliseconds(DiffDiagnostics.elapsedMilliseconds(since: start)))")

            if let first = parsed.first {
                selectedCommitID = first.id
                updateCommitSelection(for: first.id)
            }
        } catch {
            guard !Task.isCancelled else { return }
            DiffDiagnostics.error("File history failed: \(error.localizedDescription)")
            commits = []
            isLoadingCommits = false
            loadErrorMessage = error.localizedDescription.nonEmptyOrFallback("Unable to load file history.")
        }
    }

    private func reloadFileList(for worktreePath: String, commit: GitHistoryCommit) async {
        let start = DiffDiagnostics.now()
        DiffDiagnostics.log("Loading changed files for commit \(commit.shortHash)")
        isLoadingFiles = true

        do {
            let parentCommit = commit.isMergeCommit ? "\(commit.hash)^1" : "\(commit.hash)~1"
            let output = try await gitRepositoryService.diffNameStatusBetweenCommits(
                for: worktreePath,
                fromCommit: parentCommit,
                toCommit: commit.hash
            )
            guard !Task.isCancelled else { return }

            let files = DiffChangedFile.parseNameStatus(output).sorted {
                $0.displayPath.localizedStandardCompare($1.displayPath) == .orderedAscending
            }

            changedFiles = files
            isLoadingFiles = false
            DiffDiagnostics.log(
                "Loaded \(files.count) changed files for commit \(commit.shortHash) in \(DiffDiagnostics.formatMilliseconds(DiffDiagnostics.elapsedMilliseconds(since: start)))"
            )

            if let first = files.first {
                selectedFileID = first.id
                updateDocumentSelection(for: first.id)
            }
        } catch {
            guard !Task.isCancelled else { return }
            DiffDiagnostics.error("Loading changed files for commit \(commit.shortHash) failed: \(error.localizedDescription)")
            changedFiles = []
            isLoadingFiles = false
            if error.localizedDescription.contains("unknown revision") {
                await reloadFileListForRootCommit(worktreePath: worktreePath, commit: commit)
            }
        }
    }

    private func reloadRangeFileList(for worktreePath: String, fromCommit: String, toCommit: String) async {
        let start = DiffDiagnostics.now()
        DiffDiagnostics.log("Loading range diff \(String(fromCommit.prefix(7)))..\(String(toCommit.prefix(7)))")
        isLoadingFiles = true

        do {
            let output = try await gitRepositoryService.diffNameStatusBetweenCommits(
                for: worktreePath,
                fromCommit: fromCommit,
                toCommit: toCommit
            )
            guard !Task.isCancelled else { return }

            let files = DiffChangedFile.parseNameStatus(output).sorted {
                $0.displayPath.localizedStandardCompare($1.displayPath) == .orderedAscending
            }

            changedFiles = files
            isLoadingFiles = false
            DiffDiagnostics.log("Loaded \(files.count) files for range diff in \(DiffDiagnostics.formatMilliseconds(DiffDiagnostics.elapsedMilliseconds(since: start)))")

            if let first = files.first {
                selectedFileID = first.id
                updateDocumentSelection(for: first.id)
            }
        } catch {
            guard !Task.isCancelled else { return }
            DiffDiagnostics.error("Range diff file list failed: \(error.localizedDescription)")
            changedFiles = []
            isLoadingFiles = false
        }
    }

    private func reloadFileListForRootCommit(worktreePath: String, commit: GitHistoryCommit) async {
        DiffDiagnostics.log("Retrying file list for root commit \(commit.shortHash) using empty tree")
        isLoadingFiles = true
        do {
            let emptyTree = "4b825dc642cb6eb9a060e54bf899d69f7cb46208"
            let output = try await gitRepositoryService.diffNameStatusBetweenCommits(
                for: worktreePath,
                fromCommit: emptyTree,
                toCommit: commit.hash
            )
            guard !Task.isCancelled else { return }

            let files = DiffChangedFile.parseNameStatus(output).sorted {
                $0.displayPath.localizedStandardCompare($1.displayPath) == .orderedAscending
            }

            changedFiles = files
            isLoadingFiles = false

            if let first = files.first {
                selectedFileID = first.id
                updateDocumentSelection(for: first.id)
            }
        } catch {
            guard !Task.isCancelled else { return }
            DiffDiagnostics.error("Root commit file list also failed: \(error.localizedDescription)")
            changedFiles = []
            isLoadingFiles = false
        }
    }

    private func loadBranches(for worktreePath: String) async {
        do {
            let local = try await gitRepositoryService.localBranches(for: worktreePath)
            guard !Task.isCancelled else { return }
            branches = local
        } catch {
            DiffDiagnostics.error("Failed to load branches: \(error.localizedDescription)")
        }
    }

    private func loadBlame(for worktreePath: String, filePath: String, commit: String) async {
        DiffDiagnostics.log("Loading blame for \(filePath) at \(commit)")
        isLoadingBlame = true
        do {
            let output = try await gitRepositoryService.blame(for: worktreePath, filePath: filePath, commit: commit)
            guard !Task.isCancelled else { return }
            blameLines = GitBlameLine.parseLinePorcelain(output)
            isLoadingBlame = false
            DiffDiagnostics.log("Loaded \(blameLines.count) blame lines for \(filePath)")
        } catch {
            guard !Task.isCancelled else { return }
            DiffDiagnostics.error("Blame failed for \(filePath): \(error.localizedDescription)")
            blameLines = []
            isLoadingBlame = false
        }
    }

    // MARK: - Document Loading

    /// Maximum patch size (in bytes) that we'll render. Beyond this YiTong may become unresponsive.
    private static let maxPatchSize = 512 * 1024  // 512 KB

    nonisolated private static func loadHistoryDocument(
        for file: DiffChangedFile,
        worktreePath: String,
        fromCommit: String,
        toCommit: String
    ) async throws -> DiffFileDocument {
        let gitRepositoryService = GitRepositoryService()
        let diffPath = file.newPath ?? file.oldPath ?? file.displayPath

        if file.status == .added {
            let newContents = try await gitRepositoryService.showFileAtCommit(diffPath, commit: toCommit, in: worktreePath) ?? ""
            if newContents.utf8.count > maxPatchSize {
                return DiffWindowState.makeDocument(file: file, unifiedPatch: largePatchMessage(path: diffPath, size: newContents.utf8.count))
            }
            return DiffWindowState.makeDocument(
                file: file,
                unifiedPatch: syntheticAddedPatch(path: diffPath, contents: newContents)
            )
        }

        if file.status == .deleted {
            let oldContents = try await gitRepositoryService.showFileAtCommit(file.oldPath ?? diffPath, commit: fromCommit, in: worktreePath) ?? ""
            if oldContents.utf8.count > maxPatchSize {
                return DiffWindowState.makeDocument(file: file, unifiedPatch: largePatchMessage(path: file.oldPath ?? diffPath, size: oldContents.utf8.count))
            }
            return DiffWindowState.makeDocument(
                file: file,
                unifiedPatch: syntheticDeletedPatch(path: file.oldPath ?? diffPath, contents: oldContents)
            )
        }

        let patch = try await gitRepositoryService.diffPatchBetweenCommits(
            for: worktreePath,
            filePath: diffPath,
            fromCommit: fromCommit,
            toCommit: toCommit
        )

        if let patch = patch.nilIfEmpty {
            if patch.utf8.count > maxPatchSize {
                return DiffWindowState.makeDocument(file: file, unifiedPatch: largePatchMessage(path: diffPath, size: patch.utf8.count))
            }
            return DiffWindowState.makeDocument(file: file, unifiedPatch: patch)
        }

        return DiffWindowState.makeDocument(
            file: file,
            unifiedPatch: "No unified patch available for \(diffPath)."
        )
    }

    nonisolated private static func largePatchMessage(path: String, size: Int) -> String {
        let sizeKB = size / 1024
        return "Diff for \(path) is too large to display (\(sizeKB) KB). Consider viewing this file in an external diff tool."
    }

    nonisolated private static func syntheticAddedPatch(path: String, contents: String) -> String {
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
        let body = lines.map { "+\($0)" }.joined(separator: "\n")
        let count = lines.count
        return """
        diff --git a/\(path) b/\(path)
        --- /dev/null
        +++ b/\(path)
        @@ -0,0 +1,\(count) @@
        \(body)
        """
    }

    nonisolated private static func syntheticDeletedPatch(path: String, contents: String) -> String {
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
        let body = lines.map { "-\($0)" }.joined(separator: "\n")
        let count = lines.count
        return """
        diff --git a/\(path) b/\(path)
        --- a/\(path)
        +++ /dev/null
        @@ -1,\(count) +0,0 @@
        \(body)
        """
    }
}
