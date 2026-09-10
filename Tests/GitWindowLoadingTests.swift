import XCTest
@testable import Liney

final class GitWindowLoadingTests: XCTestCase {
    @MainActor
    func testDiffFirstOpenLoadsSelectionAndDocumentWithoutReopening() async throws {
        let repo = try await makeRepository()
        defer { try? FileManager.default.removeItem(at: repo) }
        let state = DiffWindowState()
        state.load(worktreePath: repo.path, branchName: "main", emptyStateMessage: "Clean")
        XCTAssertTrue(state.isLoadingFiles)
        try await waitUntil { !state.isLoadingFiles && !state.isLoadingDocument }
        XCTAssertNil(state.loadErrorMessage)
        XCTAssertEqual(state.changedFiles.count, 1)
        XCTAssertEqual(state.selectedFileID, state.changedFiles.first?.id)
        XCTAssertTrue(state.document?.unifiedPatch.contains("+updated") == true)
        state.selectFile(state.selectedFileID)
        XCTAssertNotNil(state.document)
    }

    @MainActor
    func testHistoryFirstOpenLoadsCommitAndFile() async throws {
        let repo = try await makeRepository()
        defer { try? FileManager.default.removeItem(at: repo) }
        let state = HistoryWindowState()
        state.load(worktreePath: repo.path, branchName: "main", emptyStateMessage: "Empty")
        XCTAssertTrue(state.isLoadingCommits)
        try await waitUntil { !state.isLoadingCommits && !state.isLoadingFiles && !state.isLoadingDocument }
        XCTAssertNil(state.loadErrorMessage)
        XCTAssertEqual(state.commits.count, 1)
        XCTAssertNotNil(state.selectedCommitID)
        XCTAssertNotNil(state.document)
    }

    @MainActor
    func testDocumentFailureIsReportedInsteadOfAnInvalidPatch() async throws {
        let state = DiffWindowState()
        state.worktreePath = "/tmp/liney-missing-\(UUID().uuidString)"
        let file = DiffChangedFile(status: .modified, oldPath: nil, newPath: "missing.txt")
        state.changedFiles = [file]
        state.selectFile(file.id)
        try await waitUntil { !state.isLoadingDocument }
        XCTAssertNotNil(state.documentLoadErrorMessage)
        XCTAssertNil(state.document)
    }

    @MainActor
    func testCommitRefreshesChangesWithoutReopening() async throws {
        let repo = try await makeRepository()
        defer { try? FileManager.default.removeItem(at: repo) }
        let state = DiffWindowState()
        state.load(worktreePath: repo.path, branchName: "main", emptyStateMessage: "Clean")
        try await waitUntil { !state.isLoadingFiles && !state.isLoadingDocument }
        let committed = await state.commitAllChanges(message: "Update fixture")
        XCTAssertTrue(committed)
        try await waitUntil { state.changedFiles.isEmpty && !state.isLoadingFiles }
        XCTAssertNil(state.commitErrorMessage)
        XCTAssertNil(state.document)
    }

    @MainActor
    func testHistoryRejectsOldResultsAfterContextIsCleared() async throws {
        let repo = try await makeRepository()
        defer { try? FileManager.default.removeItem(at: repo) }
        let state = HistoryWindowState()
        state.load(worktreePath: repo.path, branchName: "main", emptyStateMessage: "Empty")
        await Task.yield()
        state.load(worktreePath: nil, branchName: "", emptyStateMessage: "No repository")
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(state.commits.isEmpty)
        XCTAssertTrue(state.changedFiles.isEmpty)
        XCTAssertNil(state.document)
        XCTAssertFalse(state.isLoadingCommits)
    }

    @MainActor
    func testClearingDiffContextRejectsInFlightResult() async throws {
        let repo = try await makeRepository()
        defer { try? FileManager.default.removeItem(at: repo) }
        let state = DiffWindowState()
        state.load(worktreePath: repo.path, branchName: "main", emptyStateMessage: "Clean")
        await Task.yield()
        state.load(worktreePath: nil, branchName: "", emptyStateMessage: "No repository")
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(state.worktreePath)
        XCTAssertTrue(state.changedFiles.isEmpty)
        XCTAssertNil(state.document)
        XCTAssertFalse(state.isLoadingFiles)
    }

    private func makeRepository() async throws -> URL {
        let repo = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let runner = ShellCommandRunner()
        for args in [["init"], ["config", "user.name", "Test"], ["config", "user.email", "test@example.invalid"], ["config", "commit.gpgsign", "false"]] {
            let result = try await runner.run(executable: "/usr/bin/git", arguments: args, currentDirectory: repo.path)
            XCTAssertEqual(result.exitCode, 0)
        }
        let file = repo.appendingPathComponent("file.txt")
        try "original\n".write(to: file, atomically: true, encoding: .utf8)
        for args in [["add", "."], ["-c", "commit.gpgsign=false", "commit", "-m", "Initial"]] {
            let result = try await runner.run(executable: "/usr/bin/git", arguments: args, currentDirectory: repo.path)
            XCTAssertEqual(result.exitCode, 0)
        }
        try "updated\n".write(to: file, atomically: true, encoding: .utf8)
        return repo
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Git window did not finish loading")
    }
}
