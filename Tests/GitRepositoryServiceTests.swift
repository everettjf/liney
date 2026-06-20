//
//  GitRepositoryServiceTests.swift
//  LineyTests
//
//  Author: everettjf
//

import XCTest
@testable import Liney

final class GitRepositoryServiceTests: XCTestCase {
    func testParseWorktreeListMarksMainAndLockedEntries() {
        let output = """
        worktree /tmp/repo
        HEAD abcdef1
        branch refs/heads/main

        worktree /tmp/repo-feature
        HEAD 1234567
        branch refs/heads/feature/demo
        locked manual cleanup
        """

        let worktrees = GitRepositoryService.parseWorktreeList(output, rootPath: "/tmp/repo")

        XCTAssertEqual(worktrees.count, 2)
        XCTAssertEqual(worktrees[0].path, "/tmp/repo")
        XCTAssertTrue(worktrees[0].isMainWorktree)
        XCTAssertEqual(worktrees[1].branch, "feature/demo")
        XCTAssertTrue(worktrees[1].isLocked)
        XCTAssertEqual(worktrees[1].lockReason, "manual cleanup")
    }

    func testParseAheadBehind() {
        let parsed = GitRepositoryService.parseAheadBehind("3\t7\n")
        XCTAssertEqual(parsed.behind, 3)
        XCTAssertEqual(parsed.ahead, 7)
    }

    func testParseRemoteBranchesFiltersHeadAlias() {
        let output = """
        origin/HEAD
        origin/main
        origin/feature/one
        """

        XCTAssertEqual(
            GitRepositoryService.parseRemoteBranchList(output),
            ["origin/feature/one", "origin/main"]
        )
    }

    func testRepositoryInspectionFailedErrorIncludesPathStepAndMessage() {
        let error = GitServiceError.repositoryInspectionFailed(
            path: "/tmp/repo",
            step: "Read HEAD commit",
            message: "fatal: Needed a single revision"
        )

        XCTAssertTrue(error.localizedDescription.contains("/tmp/repo"))
        XCTAssertTrue(error.localizedDescription.contains("Read HEAD commit"))
        XCTAssertTrue(error.localizedDescription.contains("fatal: Needed a single revision"))
    }

    func testDetectsUnbornHeadErrors() {
        XCTAssertTrue(
            GitRepositoryService.isUnbornHeadError(
                "fatal: ambiguous argument 'HEAD': unknown revision or path not in the working tree."
            )
        )
        XCTAssertTrue(
            GitRepositoryService.isUnbornHeadError(
                "fatal: Needed a single revision"
            )
        )
        XCTAssertFalse(
            GitRepositoryService.isUnbornHeadError(
                "fatal: not a git repository (or any of the parent directories): .git"
            )
        )
    }

    func testInspectRepositorySupportsEmptyGitRepositories() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        try runProcess(
            executable: "/usr/bin/env",
            arguments: ["git", "init", "-b", "main"],
            currentDirectory: directoryURL.path
        )

        let snapshot = try await GitRepositoryService().inspectRepository(at: directoryURL.path)
        let normalizedPath = directoryURL.standardizedFileURL.path

        XCTAssertEqual(URL(fileURLWithPath: snapshot.rootPath).standardizedFileURL.path, normalizedPath)
        XCTAssertEqual(snapshot.currentBranch, "main")
        XCTAssertEqual(snapshot.head, "unborn")
        XCTAssertEqual(
            snapshot.worktrees.first.map { URL(fileURLWithPath: $0.path).standardizedFileURL.path },
            normalizedPath
        )
    }

    func testDiffNameStatusSupportsEmptyGitRepositories() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        try runProcess(
            executable: "/usr/bin/env",
            arguments: ["git", "init", "-b", "main"],
            currentDirectory: directoryURL.path
        )

        let fileURL = directoryURL.appendingPathComponent("staged.txt")
        try Data("hello\n".utf8).write(to: fileURL)
        try runProcess(
            executable: "/usr/bin/env",
            arguments: ["git", "add", "staged.txt"],
            currentDirectory: directoryURL.path
        )

        let output = try await GitRepositoryService().diffNameStatus(for: directoryURL.path)

        XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "A\tstaged.txt")
    }

    func testWorkingTreePatchAppliesToSiblingWorktree() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let repo = directoryURL.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)

        try runProcess(executable: "/usr/bin/env", arguments: ["git", "init", "-b", "main"], currentDirectory: repo.path)
        try runProcess(executable: "/usr/bin/env", arguments: ["git", "config", "user.email", "test@example.com"], currentDirectory: repo.path)
        try runProcess(executable: "/usr/bin/env", arguments: ["git", "config", "user.name", "Test"], currentDirectory: repo.path)

        try Data("hello\n".utf8).write(to: repo.appendingPathComponent("a.txt"))
        try runProcess(executable: "/usr/bin/env", arguments: ["git", "add", "."], currentDirectory: repo.path)
        try runProcess(executable: "/usr/bin/env", arguments: ["git", "commit", "-m", "init"], currentDirectory: repo.path)

        // A sibling worktree pinned to the same commit becomes the apply target.
        let worktree = directoryURL.appendingPathComponent("wt", isDirectory: true)
        try runProcess(
            executable: "/usr/bin/env",
            arguments: ["git", "worktree", "add", worktree.path, "HEAD"],
            currentDirectory: repo.path
        )

        // Modify a tracked file and add an untracked one in the source worktree.
        try Data("hello world\n".utf8).write(to: repo.appendingPathComponent("a.txt"))
        try Data("brand new\n".utf8).write(to: repo.appendingPathComponent("b.txt"))

        let service = GitRepositoryService()
        let patch = try await service.workingTreePatch(for: repo.path)
        XCTAssertFalse(patch.isEmpty)
        // The untracked file must be captured in the patch.
        XCTAssertTrue(patch.contains("b.txt"))

        let precheck = try await service.precheckApplyPatch(patch, to: worktree.path)
        XCTAssertTrue(precheck.appliesCleanly, precheck.message)

        try await service.applyPatch(patch, to: worktree.path, threeWay: false)

        let appliedA = try String(contentsOf: worktree.appendingPathComponent("a.txt"), encoding: .utf8)
        let appliedB = try String(contentsOf: worktree.appendingPathComponent("b.txt"), encoding: .utf8)
        XCTAssertEqual(appliedA, "hello world\n")
        XCTAssertEqual(appliedB, "brand new\n")
    }

    func testWorkingTreePatchScopesToSelectedPaths() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let repo = directoryURL.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)

        try runProcess(executable: "/usr/bin/env", arguments: ["git", "init", "-b", "main"], currentDirectory: repo.path)
        try runProcess(executable: "/usr/bin/env", arguments: ["git", "config", "user.email", "test@example.com"], currentDirectory: repo.path)
        try runProcess(executable: "/usr/bin/env", arguments: ["git", "config", "user.name", "Test"], currentDirectory: repo.path)

        try Data("a\n".utf8).write(to: repo.appendingPathComponent("a.txt"))
        try runProcess(executable: "/usr/bin/env", arguments: ["git", "add", "."], currentDirectory: repo.path)
        try runProcess(executable: "/usr/bin/env", arguments: ["git", "commit", "-m", "init"], currentDirectory: repo.path)

        let worktree = directoryURL.appendingPathComponent("wt", isDirectory: true)
        try runProcess(
            executable: "/usr/bin/env",
            arguments: ["git", "worktree", "add", worktree.path, "HEAD"],
            currentDirectory: repo.path
        )

        // Two new untracked files; only one is selected for apply.
        try Data("keep\n".utf8).write(to: repo.appendingPathComponent("keep.txt"))
        try Data("skip\n".utf8).write(to: repo.appendingPathComponent("skip.txt"))

        let service = GitRepositoryService()
        let patch = try await service.workingTreePatch(for: repo.path, paths: ["keep.txt"])
        XCTAssertTrue(patch.contains("keep.txt"))
        XCTAssertFalse(patch.contains("skip.txt"))

        try await service.applyPatch(patch, to: worktree.path, threeWay: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: worktree.appendingPathComponent("keep.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktree.appendingPathComponent("skip.txt").path))
    }

    func testPrecheckDetectsConflictingPatch() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let repo = directoryURL.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)

        try runProcess(executable: "/usr/bin/env", arguments: ["git", "init", "-b", "main"], currentDirectory: repo.path)
        try runProcess(executable: "/usr/bin/env", arguments: ["git", "config", "user.email", "test@example.com"], currentDirectory: repo.path)
        try runProcess(executable: "/usr/bin/env", arguments: ["git", "config", "user.name", "Test"], currentDirectory: repo.path)

        try Data("line one\n".utf8).write(to: repo.appendingPathComponent("a.txt"))
        try runProcess(executable: "/usr/bin/env", arguments: ["git", "add", "."], currentDirectory: repo.path)
        try runProcess(executable: "/usr/bin/env", arguments: ["git", "commit", "-m", "init"], currentDirectory: repo.path)

        let worktree = directoryURL.appendingPathComponent("wt", isDirectory: true)
        try runProcess(
            executable: "/usr/bin/env",
            arguments: ["git", "worktree", "add", worktree.path, "HEAD"],
            currentDirectory: repo.path
        )

        // Source changes a.txt; the target diverges on the same line so the patch
        // can no longer apply cleanly.
        try Data("line one changed by agent\n".utf8).write(to: repo.appendingPathComponent("a.txt"))
        try Data("line one changed in target\n".utf8).write(to: worktree.appendingPathComponent("a.txt"))

        let service = GitRepositoryService()
        let patch = try await service.workingTreePatch(for: repo.path)
        let precheck = try await service.precheckApplyPatch(patch, to: worktree.path)

        XCTAssertFalse(precheck.appliesCleanly)
        XCTAssertFalse(precheck.message.isEmpty)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
        let directoryURL = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private func runProcess(
        executable: String,
        arguments: [String],
        currentDirectory: String
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stdout = String(decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let stderr = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            XCTFail("Command failed: \(arguments.joined(separator: " "))\nstdout: \(stdout)\nstderr: \(stderr)")
            return
        }
    }
}
