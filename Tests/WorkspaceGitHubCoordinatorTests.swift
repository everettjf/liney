//
//  WorkspaceGitHubCoordinatorTests.swift
//  LineyTests
//
//  Author: everettjf
//

import XCTest
@testable import Liney

@MainActor
final class WorkspaceGitHubCoordinatorTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        // Force English language for test assertions
        LocalizationManager.shared.updateSelectedLanguage(.english)
    }

    override func tearDown() async throws {
        LocalizationManager.shared.updateSelectedLanguage(.automatic)
        try await super.tearDown()
    }
    
    func testBatchUpdateDeduplicatesTargetsAndSummarizesFailures() async throws {
        let workspace = makeCoordinatorWorkspace(name: "App", rootPath: "/tmp/app", prNumber: 101)
        let failingWorkspace = makeCoordinatorWorkspace(name: "API", rootPath: "/tmp/api", prNumber: 202)
        let client = FakeGitHubClient(
            failingUpdateNumbers: [202],
            releaseDrafts: [:]
        )
        let coordinator = WorkspaceGitHubCoordinator(client: client)

        let result = try await coordinator.executeBatch(
            .updateBranch,
            requests: [
                WorkspaceGitHubBatchRequest(workspace: workspace, worktreePath: workspace.activeWorktreePath),
                WorkspaceGitHubBatchRequest(workspace: workspace, worktreePath: workspace.activeWorktreePath),
                WorkspaceGitHubBatchRequest(workspace: failingWorkspace, worktreePath: failingWorkspace.activeWorktreePath)
            ]
        )

        let updatedNumbers = await client.updatedNumbers
        XCTAssertEqual(updatedNumbers, [101, 202])
        XCTAssertEqual(result.activities.count, 1)
        XCTAssertEqual(result.workspaceIDsToRefresh, Set([workspace.id]))
        XCTAssertEqual(result.statusUpdate?.text, "Updated PR branches. 1 succeeded, 1 failed.")
    }

    func testBatchReleaseContextBundlesDraftsInStableOrder() async throws {
        let alpha = makeCoordinatorWorkspace(name: "Alpha", rootPath: "/tmp/alpha", prNumber: 11)
        let beta = makeCoordinatorWorkspace(name: "Beta", rootPath: "/tmp/beta", prNumber: 22)
        let client = FakeGitHubClient(
            failingUpdateNumbers: [],
            releaseDrafts: [
                11: "Release Draft Context\n\nPR #11",
                22: "Release Draft Context\n\nPR #22"
            ]
        )
        let coordinator = WorkspaceGitHubCoordinator(client: client)

        let result = try await coordinator.executeBatch(
            .copyReleaseContext,
            requests: [
                WorkspaceGitHubBatchRequest(workspace: beta, worktreePath: beta.activeWorktreePath),
                WorkspaceGitHubBatchRequest(workspace: alpha, worktreePath: alpha.activeWorktreePath)
            ]
        )

        guard case .copyText(let bundledText)? = result.sideEffects.first else {
            return XCTFail("Expected bundled release context to be copied")
        }

        XCTAssertTrue(bundledText.contains("## Alpha · PR #11"))
        XCTAssertTrue(bundledText.contains("## Beta · PR #22"))
        XCTAssertLessThan(
            bundledText.range(of: "## Alpha · PR #11")?.lowerBound.utf16Offset(in: bundledText) ?? .max,
            bundledText.range(of: "## Beta · PR #22")?.lowerBound.utf16Offset(in: bundledText) ?? .max
        )
        XCTAssertEqual(result.activities.count, 2)
        XCTAssertEqual(result.statusUpdate?.text, "Combined release context copied to clipboard. 2 total.")
    }
}

@MainActor
private func makeCoordinatorWorkspace(name: String, rootPath: String, prNumber: Int) -> WorkspaceModel {
    let snapshot = RepositorySnapshot(
        rootPath: rootPath,
        currentBranch: "feature",
        head: "abc123",
        worktrees: [
            WorktreeModel(
                path: rootPath,
                branch: "feature",
                head: "abc123",
                isMainWorktree: true,
                isLocked: false,
                lockReason: nil
            )
        ],
        status: RepositoryStatusSnapshot(
            hasUncommittedChanges: false,
            changedFileCount: 0,
            aheadCount: 0,
            behindCount: 0,
            localBranches: ["feature"],
            remoteBranches: ["origin/main"]
        )
    )
    let workspace = WorkspaceModel(snapshot: snapshot)
    workspace.name = name
    workspace.updateGitHubStatus(
        GitHubWorktreeStatus(
            pullRequest: GitHubPullRequestSummary(
                number: prNumber,
                title: "PR \(prNumber)",
                url: "https://example.com/pr/\(prNumber)",
                state: "OPEN",
                isDraft: false,
                headRefName: "feature-\(prNumber)",
                mergeStateStatus: "CLEAN",
                reviewDecision: nil,
                reviewRequests: [],
                latestReviews: [],
                assignees: []
            ),
            checksSummary: nil,
            latestRun: nil
        ),
        for: rootPath
    )
    return workspace
}

private actor FakeGitHubClient: GitHubCLIClient {
    let failingUpdateNumbers: Set<Int>
    let releaseDrafts: [Int: String]
    private(set) var updatedNumbers: [Int] = []

    init(failingUpdateNumbers: Set<Int>, releaseDrafts: [Int: String]) {
        self.failingUpdateNumbers = failingUpdateNumbers
        self.releaseDrafts = releaseDrafts
    }

    var integrationStateResult: GitHubIntegrationState { .authorized(GitHubAuthStatus(username: "tester", host: "github.com")) }

    func integrationState() async -> GitHubIntegrationState {
        integrationStateResult
    }

    func status(repositoryRoot: String, branch: String) async throws -> GitHubWorktreeStatus {
        GitHubWorktreeStatus(pullRequest: nil, checksSummary: nil, latestRun: nil)
    }

    func openPullRequest(repositoryRoot: String, number: Int) async throws {}
    func markPullRequestReady(repositoryRoot: String, number: Int) async throws {}

    func updatePullRequestBranch(repositoryRoot: String, number: Int) async throws {
        updatedNumbers.append(number)
        if failingUpdateNumbers.contains(number) {
            throw GitHubCLIError.commandFailed("boom")
        }
    }

    func queuePullRequest(repositoryRoot: String, number: Int) async throws {}

    func releaseNoteDraft(repositoryRoot: String, number: Int) async throws -> String {
        releaseDrafts[number] ?? "Release Draft Context\n\nPR #\(number)"
    }

    func openRun(repositoryRoot: String, runID: Int) async throws {}
    func rerunFailedJobs(repositoryRoot: String, runID: Int) async throws {}
    func latestRunLogs(repositoryRoot: String, runID: Int) async throws -> String { "" }
}
