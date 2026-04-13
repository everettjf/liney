//
//  GitRepositoryService.swift
//  Liney
//
//  Author: everettjf
//

import Foundation
import os

enum GitServiceError: LocalizedError {
    case notAGitRepository(String)
    case commandFailed(String)
    case repositoryInspectionFailed(path: String, step: String, message: String)

    var errorDescription: String? {
        switch self {
        case .notAGitRepository(let path):
            return "\(path) is not inside a git repository."
        case .commandFailed(let message):
            return message
        case .repositoryInspectionFailed(let path, let step, let message):
            return """
            Selected path:
            \(path)

            Failed step:
            \(step)

            Error:
            \(message)
            """
        }
    }
}

struct CreateWorktreeRequest {
    var directoryPath: String
    var branchName: String
    var createNewBranch: Bool
}

struct RemoteGitSnapshot {
    var branch: String
    var head: String
    var changedFileCount: Int
    var aheadCount: Int
    var behindCount: Int
    var worktrees: [WorktreeModel] = []
}

struct RemoteWorktreeStatus {
    var changedFileCount: Int
    var aheadCount: Int
    var behindCount: Int
}

actor GitRepositoryService {
    private let runner = ShellCommandRunner()

    private static let inspectTimeout: TimeInterval = 10

    func inspectRepository(at path: String, repositoryRoot: String? = nil) async throws -> RepositorySnapshot {
        let log = AppLogger.git

        if AppLogger.isVerbose {
            log.info("Inspecting repository at \(path, privacy: .public)")
        }

        let rootPath: String
        if let repositoryRoot {
            rootPath = repositoryRoot
        } else {
            do {
                if AppLogger.isVerbose { log.debug("Locating repository root...") }
                rootPath = try await self.repositoryRoot(for: path, timeout: Self.inspectTimeout)
                if AppLogger.isVerbose { log.info("Repository root: \(rootPath, privacy: .public)") }
            } catch {
                if AppLogger.isEnabled { log.error("Failed to locate repository root: \(error.localizedDescription, privacy: .public)") }
                throw inspectionError(path: path, step: "Locate repository root", underlying: error)
            }
        }

        let branch: String
        do {
            if AppLogger.isVerbose { log.debug("Reading current branch...") }
            branch = try await currentBranch(for: path, timeout: Self.inspectTimeout)
            if AppLogger.isVerbose { log.info("Current branch: \(branch, privacy: .public)") }
        } catch {
            if AppLogger.isEnabled { log.error("Failed to read current branch: \(error.localizedDescription, privacy: .public)") }
            throw inspectionError(path: path, step: "Read current branch", underlying: error)
        }

        let head: String
        do {
            if AppLogger.isVerbose { log.debug("Reading HEAD commit...") }
            head = try await headCommit(for: path, timeout: Self.inspectTimeout)
            if AppLogger.isVerbose { log.info("HEAD commit: \(head, privacy: .public)") }
        } catch {
            if AppLogger.isEnabled { log.error("Failed to read HEAD commit: \(error.localizedDescription, privacy: .public)") }
            throw inspectionError(path: path, step: "Read HEAD commit", underlying: error)
        }

        // Worktree listing and status can be slow on large repos — use timeouts
        // and degrade gracefully so the workspace still opens.
        let worktrees: [WorktreeModel]
        do {
            if AppLogger.isVerbose { log.debug("Listing worktrees...") }
            worktrees = try await listWorktrees(for: rootPath, timeout: Self.inspectTimeout)
            if AppLogger.isVerbose { log.info("Found \(worktrees.count) worktree(s)") }
        } catch is ShellCommandError {
            if AppLogger.isEnabled { log.warning("Worktree listing timed out or failed, falling back to single worktree") }
            worktrees = [WorktreeModel(path: rootPath, branch: branch, head: head, isMainWorktree: true, isLocked: false)]
        } catch {
            if AppLogger.isEnabled { log.error("Failed to list worktrees: \(error.localizedDescription, privacy: .public)") }
            throw inspectionError(path: path, step: "List worktrees", underlying: error)
        }

        let status: RepositoryStatusSnapshot
        do {
            if AppLogger.isVerbose { log.debug("Reading repository status...") }
            status = try await repositoryStatus(for: path, timeout: Self.inspectTimeout)
            if AppLogger.isVerbose { log.info("Status: \(status.changedFileCount) changed files, ahead=\(status.aheadCount), behind=\(status.behindCount)") }
        } catch {
            if AppLogger.isEnabled { log.warning("Repository status failed, using empty status: \(error.localizedDescription, privacy: .public)") }
            // Status is non-critical — open with empty status and refresh later
            status = RepositoryStatusSnapshot(
                hasUncommittedChanges: false,
                changedFileCount: 0,
                aheadCount: 0,
                behindCount: 0,
                localBranches: [],
                remoteBranches: []
            )
        }

        if AppLogger.isVerbose { log.info("Repository inspection complete for \(rootPath, privacy: .public)") }
        return RepositorySnapshot(
            rootPath: rootPath,
            currentBranch: branch,
            head: head,
            worktrees: worktrees,
            status: status
        )
    }

    func repositoryRoot(for path: String, timeout: TimeInterval? = nil) async throws -> String {
        let result = try await git(arguments: ["rev-parse", "--show-toplevel"], currentDirectory: path, timeout: timeout)
        guard result.exitCode == 0 else {
            throw GitServiceError.notAGitRepository(path)
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func currentBranch(for rootPath: String, timeout: TimeInterval? = nil) async throws -> String {
        let symbolicRefResult = try await git(arguments: ["symbolic-ref", "--quiet", "--short", "HEAD"], currentDirectory: rootPath, timeout: timeout)
        if symbolicRefResult.exitCode == 0 {
            return symbolicRefResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let result = try await git(arguments: ["rev-parse", "--abbrev-ref", "HEAD"], currentDirectory: rootPath, timeout: timeout)
        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed(result.stderr.nonEmptyOrFallback("Unable to read current branch."))
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func headCommit(for rootPath: String, timeout: TimeInterval? = nil) async throws -> String {
        let result = try await git(arguments: ["rev-parse", "--short", "HEAD"], currentDirectory: rootPath, timeout: timeout)
        if result.exitCode != 0, Self.isUnbornHeadError(result.stderr) {
            return "unborn"
        }
        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed(result.stderr.nonEmptyOrFallback("Unable to read HEAD."))
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func fetch(for rootPath: String) async throws {
        let result = try await git(arguments: ["fetch", "--all", "--prune"], currentDirectory: rootPath)
        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed(result.stderr.nonEmptyOrFallback("git fetch failed."))
        }
    }

    func localBranches(for rootPath: String) async throws -> [String] {
        let result = try await git(arguments: ["for-each-ref", "--format=%(refname:short)", "refs/heads"], currentDirectory: rootPath)
        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed(result.stderr.nonEmptyOrFallback("Unable to list local branches."))
        }
        return Self.parseBranchList(result.stdout)
    }

    func remoteBranches(for rootPath: String) async throws -> [String] {
        let result = try await git(arguments: ["for-each-ref", "--format=%(refname:short)", "refs/remotes"], currentDirectory: rootPath)
        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed(result.stderr.nonEmptyOrFallback("Unable to list remote branches."))
        }
        return Self.parseRemoteBranchList(result.stdout)
    }

    func repositoryStatus(for path: String, timeout: TimeInterval? = nil) async throws -> RepositoryStatusSnapshot {
        async let dirtyResult = git(arguments: ["status", "--porcelain"], currentDirectory: path, timeout: timeout)
        async let upstreamResult = git(arguments: ["rev-list", "--left-right", "--count", "@{upstream}...HEAD"], currentDirectory: path, timeout: timeout)
        async let localBranchesResult = git(arguments: ["for-each-ref", "--format=%(refname:short)", "refs/heads"], currentDirectory: path, timeout: timeout)
        async let remoteBranchesResult = git(arguments: ["for-each-ref", "--format=%(refname:short)", "refs/remotes"], currentDirectory: path, timeout: timeout)

        let dirty = try await dirtyResult
        let upstream = try await upstreamResult
        let locals = try await localBranchesResult
        let remotes = try await remoteBranchesResult

        let changedFileCount = Self.parseChangedFileCount(dirty.stdout)
        let (behindCount, aheadCount) = upstream.exitCode == 0 ? Self.parseAheadBehind(upstream.stdout) : (0, 0)

        return RepositoryStatusSnapshot(
            hasUncommittedChanges: changedFileCount > 0,
            changedFileCount: changedFileCount,
            aheadCount: aheadCount,
            behindCount: behindCount,
            localBranches: Self.parseBranchList(locals.stdout),
            remoteBranches: Self.parseRemoteBranchList(remotes.stdout)
        )
    }

    func diffNameStatus(for path: String) async throws -> String {
        let result = try await git(
            arguments: ["diff", "--find-renames", "--find-copies", "--name-status", "HEAD", "--"],
            currentDirectory: path
        )
        if result.exitCode != 0, Self.isUnbornHeadError(result.stderr) {
            let cachedResult = try await git(
                arguments: ["diff", "--cached", "--find-renames", "--find-copies", "--name-status", "--"],
                currentDirectory: path
            )
            guard cachedResult.exitCode == 0 else {
                throw GitServiceError.commandFailed(cachedResult.stderr.nonEmptyOrFallback("Unable to load changed files."))
            }
            return cachedResult.stdout
        }
        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed(result.stderr.nonEmptyOrFallback("Unable to load changed files."))
        }
        return result.stdout
    }

    func untrackedFilePaths(for path: String) async throws -> [String] {
        let result = try await git(
            arguments: ["ls-files", "--others", "--exclude-standard"],
            currentDirectory: path
        )
        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed(result.stderr.nonEmptyOrFallback("Unable to list untracked files."))
        }
        return result.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    func showFileAtHEAD(_ path: String, in repositoryPath: String) async throws -> String? {
        let result = try await git(arguments: ["show", "HEAD:\(path)"], currentDirectory: repositoryPath)
        if result.exitCode == 0 {
            return result.stdout
        }

        if Self.isUnbornHeadError(result.stderr) {
            return nil
        }

        if Self.isMissingPathError(result.stderr, path: path) {
            return nil
        }

        throw GitServiceError.commandFailed(result.stderr.nonEmptyOrFallback("Unable to load \(path) from HEAD."))
    }

    func fileSizeAtHEAD(_ path: String, in repositoryPath: String) async throws -> Int? {
        let result = try await git(arguments: ["cat-file", "-s", "HEAD:\(path)"], currentDirectory: repositoryPath)
        if result.exitCode == 0 {
            return Int(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if Self.isUnbornHeadError(result.stderr) {
            return nil
        }

        if Self.isMissingPathError(result.stderr, path: path) {
            return nil
        }

        throw GitServiceError.commandFailed(result.stderr.nonEmptyOrFallback("Unable to read size for \(path) at HEAD."))
    }

    // MARK: - Git History

    private static let historyTimeout: TimeInterval = 15
    private static let blameTimeout: TimeInterval = 30
    private static let diffTimeout: TimeInterval = 15

    func commitLog(for path: String, maxCount: Int = 200, branch: String? = nil, skip: Int = 0) async throws -> String {
        let format = "---COMMIT---%H---FIELD---%h---FIELD---%an---FIELD---%ae---FIELD---%aI---FIELD---%s---FIELD---%b---FIELD---%P"
        var arguments = ["log", "--format=\(format)", "--max-count=\(maxCount)"]
        if skip > 0 {
            arguments.append("--skip=\(skip)")
        }
        if let branch {
            arguments.append(branch)
        }
        let result = try await git(
            arguments: arguments,
            currentDirectory: path,
            timeout: Self.historyTimeout
        )
        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed(result.stderr.nonEmptyOrFallback("Unable to load commit history."))
        }
        return result.stdout
    }

    func commitLogNumstat(for path: String, maxCount: Int = 200, branch: String? = nil, skip: Int = 0) async throws -> String {
        var arguments = ["log", "--numstat", "--format=---COMMIT---%H", "--max-count=\(maxCount)"]
        if skip > 0 {
            arguments.append("--skip=\(skip)")
        }
        if let branch {
            arguments.append(branch)
        }
        let result = try await git(
            arguments: arguments,
            currentDirectory: path,
            timeout: Self.historyTimeout
        )
        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed(result.stderr.nonEmptyOrFallback("Unable to load commit stats."))
        }
        return result.stdout
    }

    func fileCommitLog(for path: String, filePath: String, maxCount: Int = 200) async throws -> String {
        let format = "---COMMIT---%H---FIELD---%h---FIELD---%an---FIELD---%ae---FIELD---%aI---FIELD---%s---FIELD---%b---FIELD---%P"
        let result = try await git(
            arguments: ["log", "--follow", "--format=\(format)", "--max-count=\(maxCount)", "--", filePath],
            currentDirectory: path,
            timeout: Self.historyTimeout
        )
        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed(result.stderr.nonEmptyOrFallback("Unable to load file history."))
        }
        return result.stdout
    }

    func blame(for repositoryPath: String, filePath: String, commit: String = "HEAD") async throws -> String {
        let result = try await git(
            arguments: ["blame", "--line-porcelain", commit, "--", filePath],
            currentDirectory: repositoryPath,
            timeout: Self.blameTimeout
        )
        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed(result.stderr.nonEmptyOrFallback("Unable to load blame for \(filePath)."))
        }
        return result.stdout
    }

    func diffNameStatusBetweenCommits(for path: String, fromCommit: String, toCommit: String) async throws -> String {
        let result = try await git(
            arguments: ["diff", "--find-renames", "--find-copies", "--name-status", fromCommit, toCommit, "--"],
            currentDirectory: path,
            timeout: Self.diffTimeout
        )
        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed(result.stderr.nonEmptyOrFallback("Unable to load changed files between commits."))
        }
        return result.stdout
    }

    func diffPatchBetweenCommits(for repositoryPath: String, filePath: String, fromCommit: String, toCommit: String) async throws -> String {
        let result = try await git(
            arguments: ["diff", "--find-renames", "--find-copies", "--no-color", fromCommit, toCommit, "--", filePath],
            currentDirectory: repositoryPath,
            timeout: Self.diffTimeout
        )
        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed(result.stderr.nonEmptyOrFallback("Unable to load diff patch for \(filePath) between commits."))
        }
        return result.stdout
    }

    func showFileAtCommit(_ path: String, commit: String, in repositoryPath: String) async throws -> String? {
        let result = try await git(arguments: ["show", "\(commit):\(path)"], currentDirectory: repositoryPath, timeout: Self.diffTimeout)
        if result.exitCode == 0 {
            return result.stdout
        }
        if result.stderr.lowercased().contains("does not exist") || result.stderr.lowercased().contains("exists on disk") {
            return nil
        }
        throw GitServiceError.commandFailed(result.stderr.nonEmptyOrFallback("Unable to load \(path) at \(commit)."))
    }

    // MARK: - Working Tree Diff

    func diffPatch(for repositoryPath: String, filePath: String) async throws -> String {
        let result = try await git(
            arguments: ["diff", "--find-renames", "--find-copies", "--no-color", "HEAD", "--", filePath],
            currentDirectory: repositoryPath
        )
        if result.exitCode != 0, Self.isUnbornHeadError(result.stderr) {
            let cachedResult = try await git(
                arguments: ["diff", "--cached", "--find-renames", "--find-copies", "--no-color", "--", filePath],
                currentDirectory: repositoryPath
            )
            guard cachedResult.exitCode == 0 else {
                throw GitServiceError.commandFailed(cachedResult.stderr.nonEmptyOrFallback("Unable to load diff patch for \(filePath)."))
            }
            return cachedResult.stdout
        }
        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed(result.stderr.nonEmptyOrFallback("Unable to load diff patch for \(filePath)."))
        }
        return result.stdout
    }

    func repositoryStatuses(for paths: [String]) async throws -> [String: RepositoryStatusSnapshot] {
        try await withThrowingTaskGroup(of: (String, RepositoryStatusSnapshot).self) { group in
            for path in Set(paths) {
                group.addTask { [self] in
                    (path, try await repositoryStatus(for: path))
                }
            }

            var statuses: [String: RepositoryStatusSnapshot] = [:]
            for try await (path, status) in group {
                statuses[path] = status
            }
            return statuses
        }
    }

    func listWorktrees(for rootPath: String, timeout: TimeInterval? = nil) async throws -> [WorktreeModel] {
        let result = try await git(arguments: ["worktree", "list", "--porcelain"], currentDirectory: rootPath, timeout: timeout)
        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed(result.stderr.nonEmptyOrFallback("Unable to list worktrees."))
        }
        return Self.parseWorktreeList(result.stdout, rootPath: rootPath)
    }

    nonisolated static func parseWorktreeList(_ output: String, rootPath: String) -> [WorktreeModel] {
        var worktrees: [WorktreeModel] = []
        let blocks = output.components(separatedBy: "\n\n")
        for block in blocks where block.contains("worktree ") {
            var path: String?
            var head = ""
            var branch: String?
            var isLocked = false
            var lockReason: String?

            for rawLine in block.split(separator: "\n") {
                let line = String(rawLine)
                if line.hasPrefix("worktree ") {
                    path = String(line.dropFirst("worktree ".count))
                } else if line.hasPrefix("HEAD ") {
                    head = String(line.dropFirst("HEAD ".count))
                } else if line.hasPrefix("branch ") {
                    let ref = String(line.dropFirst("branch ".count))
                    branch = ref.replacingOccurrences(of: "refs/heads/", with: "")
                } else if line.hasPrefix("locked") {
                    isLocked = true
                    lockReason = line.replacingOccurrences(of: "locked ", with: "")
                }
            }

            guard let path else { continue }
            worktrees.append(
                WorktreeModel(
                    path: path,
                    branch: branch,
                    head: head,
                    isMainWorktree: path == rootPath,
                    isLocked: isLocked,
                    lockReason: lockReason?.nilIfEmpty
                )
            )
        }

        return worktrees.sorted { lhs, rhs in
            if lhs.isMainWorktree != rhs.isMainWorktree {
                return lhs.isMainWorktree && !rhs.isMainWorktree
            }
            return lhs.path < rhs.path
        }
    }

    func createWorktree(rootPath: String, request: CreateWorktreeRequest) async throws {
        var arguments = ["worktree", "add"]

        if request.createNewBranch {
            arguments.append(contentsOf: ["-b", request.branchName])
            arguments.append(request.directoryPath)
            arguments.append("HEAD")
        } else {
            arguments.append(request.directoryPath)
            arguments.append(request.branchName)
        }

        let result = try await git(arguments: arguments, currentDirectory: rootPath)
        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed(result.stderr.nonEmptyOrFallback("Unable to create worktree."))
        }
    }

    func createRemoteWorktree(rootPath: String, request: CreateWorktreeRequest, sshConfig: SSHSessionConfiguration) async throws {
        var gitArgs = "git worktree add"
        if request.createNewBranch {
            gitArgs += " -b \(request.branchName.shellQuoted) \(request.directoryPath.shellQuoted) HEAD"
        } else {
            gitArgs += " \(request.directoryPath.shellQuoted) \(request.branchName.shellQuoted)"
        }
        let script = "cd \(rootPath.shellQuoted) && \(gitArgs)"

        var arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
        ]
        if let port = sshConfig.port {
            arguments.append(contentsOf: ["-p", "\(port)"])
        }
        if let identityFile = sshConfig.identityFilePath {
            arguments.append(contentsOf: ["-i", identityFile])
        }
        arguments.append(sshConfig.destination)
        arguments.append(script)

        let result = try await runner.run(
            executable: "/usr/bin/ssh",
            arguments: arguments,
            timeout: Self.remoteInspectTimeout
        )
        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed(
                result.stderr.nonEmptyOrFallback("Unable to create remote worktree.")
            )
        }
    }

    func removeRemoteWorktree(rootPath: String, path: String, force: Bool = false, sshConfig: SSHSessionConfiguration) async throws {
        var gitArgs = "git worktree remove"
        if force {
            gitArgs += " --force"
        }
        gitArgs += " \(path.shellQuoted)"
        let script = "cd \(rootPath.shellQuoted) && \(gitArgs)"

        var arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
        ]
        if let port = sshConfig.port {
            arguments.append(contentsOf: ["-p", "\(port)"])
        }
        if let identityFile = sshConfig.identityFilePath {
            arguments.append(contentsOf: ["-i", identityFile])
        }
        arguments.append(sshConfig.destination)
        arguments.append(script)

        let result = try await runner.run(
            executable: "/usr/bin/ssh",
            arguments: arguments,
            timeout: Self.remoteInspectTimeout
        )
        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed(
                result.stderr.nonEmptyOrFallback("Unable to remove remote worktree.")
            )
        }
    }

    func removeWorktree(rootPath: String, path: String, force: Bool = false) async throws {
        var arguments = ["worktree", "remove"]
        if force {
            arguments.append("--force")
        }
        arguments.append(path)
        let result = try await git(arguments: arguments, currentDirectory: rootPath)
        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed(result.stderr.nonEmptyOrFallback("Unable to remove worktree."))
        }
    }

    private func git(arguments: [String], currentDirectory: String, timeout: TimeInterval? = nil) async throws -> ShellCommandResult {
        if let timeout {
            return try await runner.run(
                executable: "/usr/bin/env",
                arguments: ["git"] + arguments,
                currentDirectory: currentDirectory,
                environment: ["LC_ALL": "en_US.UTF-8"],
                timeout: timeout
            )
        }
        return try await runner.run(
            executable: "/usr/bin/env",
            arguments: ["git"] + arguments,
            currentDirectory: currentDirectory,
            environment: ["LC_ALL": "en_US.UTF-8"]
        )
    }

    nonisolated private func inspectionError(path: String, step: String, underlying: any Error) -> GitServiceError {
        if let gitError = underlying as? GitServiceError {
            switch gitError {
            case .repositoryInspectionFailed:
                return gitError
            case .notAGitRepository:
                return gitError
            default:
                return .repositoryInspectionFailed(
                    path: path,
                    step: step,
                    message: gitError.localizedDescription
                )
            }
        }

        return .repositoryInspectionFailed(
            path: path,
            step: step,
            message: underlying.localizedDescription
        )
    }

    nonisolated static func parseBranchList(_ output: String) -> [String] {
        output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    nonisolated static func parseRemoteBranchList(_ output: String) -> [String] {
        parseBranchList(output)
            .filter { !$0.hasSuffix("/HEAD") }
    }

    nonisolated static func parseChangedFileCount(_ output: String) -> Int {
        output.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    nonisolated static func parseAheadBehind(_ output: String) -> (behind: Int, ahead: Int) {
        let components = output
            .split(whereSeparator: \.isWhitespace)
            .compactMap { Int($0) }
        guard components.count >= 2 else { return (0, 0) }
        return (components[0], components[1])
    }

    nonisolated static func isUnbornHeadError(_ stderr: String) -> Bool {
        let normalizedError = stderr.lowercased()
        return normalizedError.contains("ambiguous argument 'head'") ||
            normalizedError.contains("unknown revision or path not in the working tree") ||
            normalizedError.contains("needed a single revision") ||
            normalizedError.contains("bad revision 'head'") ||
            normalizedError.contains("not a valid object name: 'head'") ||
            normalizedError.contains("invalid object name 'head'")
    }

    nonisolated private static func isMissingPathError(_ stderr: String, path: String) -> Bool {
        let normalizedError = stderr.lowercased()
        return normalizedError.contains("exists on disk, but not in 'head'") ||
            normalizedError.contains("does not exist in 'head'") ||
            normalizedError.contains("path '\(path.lowercased())' does not exist in 'head'") ||
            normalizedError.contains("fatal: path '\(path.lowercased())' exists on disk, but not in 'head'") ||
            normalizedError.contains("fatal: path '\(path.lowercased())' does not exist")
    }

    // MARK: - Remote Git Inspection

    nonisolated static func parseRemoteInspection(_ output: String) -> RemoteGitSnapshot {
        var branch = ""
        var head = ""
        var changedFileCount = 0
        var aheadCount = 0
        var behindCount = 0
        var currentSection = ""
        var worktreeLines: [String] = []

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            switch trimmed {
            case "__BRANCH__", "__HEAD__", "__WORKTREE__", "__STATUS__", "__AHEAD_BEHIND__":
                currentSection = trimmed
            default:
                switch currentSection {
                case "__WORKTREE__":
                    worktreeLines.append(trimmed)
                default:
                    guard !trimmed.isEmpty else { continue }
                    switch currentSection {
                    case "__BRANCH__":
                        branch = trimmed
                    case "__HEAD__":
                        head = trimmed
                    case "__STATUS__":
                        changedFileCount += 1
                    case "__AHEAD_BEHIND__":
                        let parts = trimmed.split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
                        if parts.count >= 2 {
                            aheadCount = parts[0]
                            behindCount = parts[1]
                        }
                    default:
                        break
                    }
                }
            }
        }

        let worktreeOutput = worktreeLines.joined(separator: "\n")
        var rootPath = ""
        for wl in worktreeLines {
            if wl.hasPrefix("worktree ") {
                rootPath = String(wl.dropFirst("worktree ".count))
                break
            }
        }
        let worktrees = parseWorktreeList(worktreeOutput, rootPath: rootPath)

        return RemoteGitSnapshot(
            branch: branch,
            head: head,
            changedFileCount: changedFileCount,
            aheadCount: aheadCount,
            behindCount: behindCount,
            worktrees: worktrees
        )
    }

    private static let remoteInspectTimeout: TimeInterval = 15

    func inspectRemoteRepository(remotePath: String, sshConfig: SSHSessionConfiguration) async throws -> RemoteGitSnapshot {
        let script = "cd \(remotePath.shellQuoted) && " +
            "echo __BRANCH__ && git rev-parse --abbrev-ref HEAD 2>/dev/null && " +
            "echo __HEAD__ && git rev-parse --short HEAD 2>/dev/null && " +
            "echo __WORKTREE__ && git worktree list --porcelain 2>/dev/null && " +
            "echo __STATUS__ && git status --porcelain 2>/dev/null && " +
            "echo __AHEAD_BEHIND__ && git rev-list --left-right --count HEAD...@{upstream} 2>/dev/null || true"

        var arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
        ]

        if let port = sshConfig.port {
            arguments.append(contentsOf: ["-p", "\(port)"])
        }

        if let identityFile = sshConfig.identityFilePath {
            arguments.append(contentsOf: ["-i", identityFile])
        }

        arguments.append(sshConfig.destination)
        arguments.append(script)

        let result = try await runner.run(
            executable: "/usr/bin/ssh",
            arguments: arguments,
            timeout: Self.remoteInspectTimeout
        )

        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed(
                result.stderr.nonEmptyOrFallback("Remote git inspection failed.")
            )
        }

        return Self.parseRemoteInspection(result.stdout)
    }

    func inspectRemoteWorktreeStatuses(
        worktreePaths: [String],
        sshConfig: SSHSessionConfiguration
    ) async throws -> [String: RemoteWorktreeStatus] {
        guard !worktreePaths.isEmpty else { return [:] }

        var scriptParts: [String] = []
        for path in worktreePaths {
            scriptParts.append("echo '__WT_PATH__' && echo \(path.shellQuoted) && cd \(path.shellQuoted) 2>/dev/null && echo '__WT_STATUS__' && git status --porcelain 2>/dev/null && echo '__WT_AHEAD_BEHIND__' && git rev-list --left-right --count HEAD...@{upstream} 2>/dev/null || true")
        }
        let script = scriptParts.joined(separator: " && ")

        var arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
        ]
        if let port = sshConfig.port {
            arguments.append(contentsOf: ["-p", "\(port)"])
        }
        if let identityFile = sshConfig.identityFilePath {
            arguments.append(contentsOf: ["-i", identityFile])
        }
        arguments.append(sshConfig.destination)
        arguments.append(script)

        let result = try await runner.run(
            executable: "/usr/bin/ssh",
            arguments: arguments,
            timeout: Self.remoteInspectTimeout
        )
        return Self.parseRemoteWorktreeStatuses(result.stdout)
    }

    nonisolated static func parseRemoteWorktreeStatuses(_ output: String) -> [String: RemoteWorktreeStatus] {
        var results: [String: RemoteWorktreeStatus] = [:]
        var currentPath = ""
        var changedFileCount = 0
        var aheadCount = 0
        var behindCount = 0
        var currentSection = ""

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            switch trimmed {
            case "__WT_PATH__":
                if !currentPath.isEmpty {
                    results[currentPath] = RemoteWorktreeStatus(changedFileCount: changedFileCount, aheadCount: aheadCount, behindCount: behindCount)
                }
                currentPath = ""
                changedFileCount = 0
                aheadCount = 0
                behindCount = 0
                currentSection = "__WT_PATH__"
            case "__WT_STATUS__":
                currentSection = "__WT_STATUS__"
            case "__WT_AHEAD_BEHIND__":
                currentSection = "__WT_AHEAD_BEHIND__"
            default:
                switch currentSection {
                case "__WT_PATH__":
                    if !trimmed.isEmpty { currentPath = trimmed }
                case "__WT_STATUS__":
                    if !trimmed.isEmpty { changedFileCount += 1 }
                case "__WT_AHEAD_BEHIND__":
                    if !trimmed.isEmpty {
                        let parts = trimmed.split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
                        if parts.count >= 2 { aheadCount = parts[0]; behindCount = parts[1] }
                    }
                default: break
                }
            }
        }
        if !currentPath.isEmpty {
            results[currentPath] = RemoteWorktreeStatus(changedFileCount: changedFileCount, aheadCount: aheadCount, behindCount: behindCount)
        }
        return results
    }
}
