//
//  PendingWorktreeRemovalTests.swift
//  LineyTests
//
//  Author: everettjf
//

import XCTest
@testable import Liney

@MainActor
final class PendingWorktreeRemovalTests: XCTestCase {
    override func tearDown() {
        LocalizationManager.shared.updateSelectedLanguage(.automatic)
        super.tearDown()
    }

    func testDetailMessageIncludesActiveDirtyAndAheadWarnings() {
        LocalizationManager.shared.updateSelectedLanguage(.english)

        let request = PendingWorktreeRemoval(
            workspaceID: UUID(),
            worktreePaths: ["/tmp/repo-feature"],
            worktreeNames: ["feature"],
            activePaneCount: 2,
            includesActiveWorktree: true,
            dirtyWorktreeNames: ["feature"],
            dirtyFileCount: 3,
            aheadWorktreeNames: ["feature"],
            aheadCommitCount: 2
        )

        XCTAssertTrue(request.detailMessage.contains("switch back to the main checkout first"))
        XCTAssertTrue(request.detailMessage.contains("2 running pane(s)"))
        XCTAssertTrue(request.detailMessage.contains("Uncommitted changes detected in feature (3 file(s))"))
        XCTAssertTrue(request.detailMessage.contains("Unpushed commits detected in feature (2 commit(s) ahead)"))
        XCTAssertTrue(request.allowsForceRemove)
    }

    func testForceRemoveOnlyAppearsForDirtyWorktrees() {
        let request = PendingWorktreeRemoval(
            workspaceID: UUID(),
            worktreePaths: ["/tmp/repo-feature"],
            worktreeNames: ["feature"],
            activePaneCount: 0,
            includesActiveWorktree: false,
            dirtyWorktreeNames: [],
            dirtyFileCount: 0,
            aheadWorktreeNames: ["feature"],
            aheadCommitCount: 1
        )

        XCTAssertFalse(request.allowsForceRemove)
    }

    func testDetailMessageLocalizesToSimplifiedChinese() {
        LocalizationManager.shared.updateSelectedLanguage(.simplifiedChinese)

        let request = PendingWorktreeRemoval(
            workspaceID: UUID(),
            worktreePaths: ["/tmp/repo-feature"],
            worktreeNames: ["feature"],
            activePaneCount: 2,
            includesActiveWorktree: true,
            dirtyWorktreeNames: ["feature"],
            dirtyFileCount: 3,
            aheadWorktreeNames: ["feature"],
            aheadCommitCount: 2
        )

        XCTAssertTrue(request.detailMessage.contains("会先切回主检出目录"))
        XCTAssertTrue(request.detailMessage.contains("2 个运行中面板"))
        XCTAssertTrue(request.detailMessage.contains("未提交更改"))
        XCTAssertTrue(request.detailMessage.contains("未推送提交"))
    }

    func testApplyingSnapshotAfterActiveWorktreeRemovalFallsBackWithoutDroppingSurvivors() {
        let rootPath = "/tmp/repo"
        let removedPath = "/tmp/repo-removed"
        let survivingPath = "/tmp/repo-surviving"
        let initialStatus = RepositoryStatusSnapshot(
            hasUncommittedChanges: false,
            changedFileCount: 0,
            aheadCount: 0,
            behindCount: 0,
            localBranches: ["main"],
            remoteBranches: []
        )
        let initialWorktrees = [
            WorktreeModel(path: rootPath, branch: "main", head: "abc", isMainWorktree: true, isLocked: false),
            WorktreeModel(path: removedPath, branch: "removed", head: "abc", isMainWorktree: false, isLocked: false),
            WorktreeModel(path: survivingPath, branch: "surviving", head: "abc", isMainWorktree: false, isLocked: false),
        ]
        let workspace = WorkspaceModel(
            snapshot: RepositorySnapshot(
                rootPath: rootPath,
                currentBranch: "main",
                head: "abc",
                worktrees: initialWorktrees,
                status: initialStatus
            )
        )
        workspace.activeWorktreePath = removedPath

        let refreshedStatus = RepositoryStatusSnapshot(
            hasUncommittedChanges: true,
            changedFileCount: 1,
            aheadCount: 0,
            behindCount: 0,
            localBranches: ["main", "surviving"],
            remoteBranches: []
        )
        workspace.apply(
            snapshot: RepositorySnapshot(
                rootPath: rootPath,
                currentBranch: "main",
                head: "abc",
                worktrees: [initialWorktrees[0], initialWorktrees[2]],
                status: refreshedStatus
            )
        )

        XCTAssertEqual(workspace.activeWorktreePath, rootPath)
        XCTAssertEqual(Set(workspace.worktrees.map(\.path)), Set([rootPath, survivingPath]))
        XCTAssertEqual(workspace.worktreeStatuses[rootPath], refreshedStatus)
        XCTAssertNil(workspace.worktreeStatuses[removedPath])
    }

    func testForgetWorktreeImmediatelyRemovesOnlyRequestedModel() {
        let rootPath = "/tmp/repo"
        let removedPath = "/tmp/repo-removed"
        let survivingPath = "/tmp/repo-surviving"
        let status = RepositoryStatusSnapshot(
            hasUncommittedChanges: false,
            changedFileCount: 0,
            aheadCount: 0,
            behindCount: 0,
            localBranches: ["main"],
            remoteBranches: []
        )
        let workspace = WorkspaceModel(
            snapshot: RepositorySnapshot(
                rootPath: rootPath,
                currentBranch: "main",
                head: "abc",
                worktrees: [
                    WorktreeModel(path: rootPath, branch: "main", head: "abc", isMainWorktree: true, isLocked: false),
                    WorktreeModel(path: removedPath, branch: "removed", head: "abc", isMainWorktree: false, isLocked: false),
                    WorktreeModel(path: survivingPath, branch: "surviving", head: "abc", isMainWorktree: false, isLocked: false),
                ],
                status: status
            )
        )

        workspace.forgetWorktrees(paths: [removedPath])

        XCTAssertEqual(Set(workspace.worktrees.map(\.path)), Set([rootPath, survivingPath]))
    }
}
