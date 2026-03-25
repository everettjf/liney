//
//  GitRepositoryService.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

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

actor GitRepositoryService {
    private let runner = ShellCommandRunner()

    func inspectRepository(at path: String, repositoryRoot: String? = nil) async throws -> RepositorySnapshot {
        let rootPath: String
        if let repositoryRoot {
            rootPath = repositoryRoot
        } else {
            do {
                rootPath = try await self.repositoryRoot(for: path)
            } catch {
                throw inspectionError(path: path, step: "Locate repository root", underlying: error)
            }
        }

        let branch: String
        do {
            branch = try await currentBranch(for: path)
        } catch {
            throw inspectionError(path: path, step: "Read current branch", underlying: error)
        }

        let head: String
        do {
            head = try await headCommit(for: path)
        } catch {
            throw inspectionError(path: path, step: "Read HEAD commit", underlying: error)
        }

        let worktrees: [WorktreeModel]
        do {
            worktrees = try await listWorktrees(for: rootPath)
        } catch {
            throw inspectionError(path: path, step: "List worktrees", underlying: error)
        }

        let status: RepositoryStatusSnapshot
        do {
            status = try await repositoryStatus(for: path)
        } catch {
            throw inspectionError(path: path, step: "Read repository status", underlying: error)
        }

        return RepositorySnapshot(
            rootPath: rootPath,
            currentBranch: branch,
            head: head,
            worktrees: worktrees,
            status: status
        )
    }

    func repositoryRoot(for path: String) async throws -> String {
        let result = try await git(arguments: ["rev-parse", "--show-toplevel"], currentDirectory: path)
        guard result.exitCode == 0 else {
            throw GitServiceError.notAGitRepository(path)
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func currentBranch(for rootPath: String) async throws -> String {
        let symbolicRefResult = try await git(arguments: ["symbolic-ref", "--quiet", "--short", "HEAD"], currentDirectory: rootPath)
        if symbolicRefResult.exitCode == 0 {
            return symbolicRefResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let result = try await git(arguments: ["rev-parse", "--abbrev-ref", "HEAD"], currentDirectory: rootPath)
        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed(result.stderr.nonEmptyOrFallback("Unable to read current branch."))
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func headCommit(for rootPath: String) async throws -> String {
        let result = try await git(arguments: ["rev-parse", "--short", "HEAD"], currentDirectory: rootPath)
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

    func repositoryStatus(for path: String) async throws -> RepositoryStatusSnapshot {
        async let dirtyResult = git(arguments: ["status", "--porcelain"], currentDirectory: path)
        async let upstreamResult = git(arguments: ["rev-list", "--left-right", "--count", "@{upstream}...HEAD"], currentDirectory: path)
        async let localBranchesResult = git(arguments: ["for-each-ref", "--format=%(refname:short)", "refs/heads"], currentDirectory: path)
        async let remoteBranchesResult = git(arguments: ["for-each-ref", "--format=%(refname:short)", "refs/remotes"], currentDirectory: path)

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

    func listWorktrees(for rootPath: String) async throws -> [WorktreeModel] {
        let result = try await git(arguments: ["worktree", "list", "--porcelain"], currentDirectory: rootPath)
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

    private func git(arguments: [String], currentDirectory: String) async throws -> ShellCommandResult {
        try await runner.run(
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
}
