//
//  OverviewViewModelTests.swift
//  LineyTests
//
//  Author: everettjf
//

import XCTest
@testable import Liney

@MainActor
final class OverviewViewModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        LocalizationManager.shared.updateSelectedLanguage(.automatic)
    }

    func testPullRequestInboxSectionsSortAndExposeReviewMetadata() {
        LocalizationManager.shared.updateSelectedLanguage(.english)

        let failing = makeWorkspace(
            name: "Failing",
            rootPath: "/tmp/failing",
            pullRequest: makePullRequest(number: 11, title: "Fix CI", mergeStateStatus: "CLEAN"),
            checksSummary: GitHubPullRequestChecksSummary(
                passingCount: 0,
                failingCount: 1,
                pendingCount: 0,
                skippedCount: 0,
                failingChecks: [
                    GitHubPullRequestCheck(
                        name: "unit-tests",
                        workflow: "ci",
                        state: "FAILURE",
                        bucket: "fail",
                        link: "https://example.com/check/11",
                        description: nil
                    )
                ]
            )
        )
        let behind = makeWorkspace(
            name: "Behind",
            rootPath: "/tmp/behind",
            pullRequest: makePullRequest(number: 22, title: "Update branch", mergeStateStatus: "BEHIND")
        )
        let review = makeWorkspace(
            name: "Review",
            rootPath: "/tmp/review",
            pullRequest: makePullRequest(
                number: 33,
                title: "Need eyes",
                mergeStateStatus: "CLEAN",
                reviewRequests: ["alex"],
                assignees: ["owner"]
            )
        )
        let ready = makeWorkspace(
            name: "Ready",
            rootPath: "/tmp/ready",
            pullRequest: makePullRequest(
                number: 44,
                title: "Ship it",
                mergeStateStatus: "CLEAN",
                latestReviews: [("sam", "APPROVED")]
            ),
            checksSummary: GitHubPullRequestChecksSummary(
                passingCount: 3,
                failingCount: 0,
                pendingCount: 0,
                skippedCount: 0,
                failingChecks: []
            )
        )

        let model = OverviewViewModel(snapshots: [ready, review, behind, failing])
        let sectionsByCategory = Dictionary(uniqueKeysWithValues: model.pullRequestInboxSections.map { ($0.category, $0.items) })
        guard let reviewItem = sectionsByCategory[.review]?.first else {
            return XCTFail("Expected review item")
        }
        guard let readyItem = sectionsByCategory[.ready]?.first else {
            return XCTFail("Expected ready item")
        }

        XCTAssertEqual(model.pullRequestInboxSections.map(\.category), [.failing, .behind, .review, .ready])
        XCTAssertEqual(model.readyPullRequestTargets.count, 1)
        XCTAssertEqual(model.behindPullRequestTargets.count, 1)
        XCTAssertEqual(model.releaseContextTargets.count, 1)
        XCTAssertEqual(reviewItem.reviewLine, "Reviewers: alex · Assignees: owner")
        XCTAssertEqual(readyItem.detail, "3 checks passing · Approved by sam · Ready for merge queue and release context")
    }

    func testTodayFocusDeduplicatesWorkspaceAndPrioritizesFailures() {
        LocalizationManager.shared.updateSelectedLanguage(.english)

        let workspace = makeWorkspace(
            name: "Alpha",
            rootPath: "/tmp/alpha",
            pullRequest: makePullRequest(number: 55, title: "Fix all the things", mergeStateStatus: "CLEAN"),
            checksSummary: GitHubPullRequestChecksSummary(
                passingCount: 0,
                failingCount: 2,
                pendingCount: 0,
                skippedCount: 0,
                failingChecks: [
                    GitHubPullRequestCheck(
                        name: "lint",
                        workflow: "ci",
                        state: "FAILURE",
                        bucket: "fail",
                        link: nil,
                        description: nil
                    )
                ]
            ),
            changedFileCount: 4,
            preferredWorkflow: WorkspaceWorkflow(name: "Ship")
        )
        let secondary = makeWorkspace(
            name: "Beta",
            rootPath: "/tmp/beta",
            pullRequest: makePullRequest(number: 66, title: "Ready", mergeStateStatus: "CLEAN", latestReviews: [("zoe", "APPROVED")])
        )

        let model = OverviewViewModel(snapshots: [secondary, workspace])
        guard let firstItem = model.todayFocusItems.first else {
            return XCTFail("Expected first focus item")
        }

        XCTAssertEqual(model.todayFocusItems.count, 2)
        XCTAssertEqual(firstItem.workspace.id, workspace.id)
        XCTAssertEqual(firstItem.headline, "Fix failing checks")
    }

    func testRecentActivitiesExcludeReleaseEntriesAndRemainSorted() {
        let workflowEntry = WorkspaceActivityEntry(
            timestamp: 300,
            kind: .workflow,
            title: "Ran workflow",
            detail: "Ship"
        )
        let commandEntry = WorkspaceActivityEntry(
            timestamp: 200,
            kind: .command,
            title: "Ran command",
            detail: "make test"
        )
        let releaseEntry = WorkspaceActivityEntry(
            timestamp: 400,
            kind: .release,
            title: "Checked for updates",
            detail: "1.0.5"
        )

        let workspace = OverviewWorkspaceSnapshot(
            id: UUID(),
            name: "Alpha",
            supportsRepositoryFeatures: true,
            activeWorktreePath: "/tmp/alpha",
            hasUncommittedChanges: false,
            changedFileCount: 0,
            currentBranch: "main",
            activeSessionCount: 1,
            preferredWorkflow: nil,
            recentActivity: [commandEntry, releaseEntry, workflowEntry],
            worktrees: [
                WorktreeModel(
                    path: "/tmp/alpha",
                    branch: "main",
                    head: "abc123",
                    isMainWorktree: true,
                    isLocked: false,
                    lockReason: nil
                )
            ],
            worktreeStatuses: [:],
            gitHubStatuses: [:]
        )

        let model = OverviewViewModel(snapshots: [workspace])

        XCTAssertEqual(model.recentActivities.map(\.entry.kind), [.workflow, .command])
        XCTAssertEqual(model.recentActivities.map(\.entry.title), ["Ran workflow", "Ran command"])
    }

    func testPullRequestInboxLocalizesDerivedCopyWhenChineseSelected() {
        LocalizationManager.shared.updateSelectedLanguage(.simplifiedChinese)

        let review = makeWorkspace(
            name: "Review",
            rootPath: "/tmp/review-zh",
            pullRequest: makePullRequest(
                number: 33,
                title: "Need eyes",
                mergeStateStatus: "CLEAN",
                reviewRequests: ["alex"],
                assignees: ["owner"]
            )
        )
        let ready = makeWorkspace(
            name: "Ready",
            rootPath: "/tmp/ready-zh",
            pullRequest: makePullRequest(
                number: 44,
                title: "Ship it",
                mergeStateStatus: "CLEAN",
                latestReviews: [("sam", "APPROVED")]
            ),
            checksSummary: GitHubPullRequestChecksSummary(
                passingCount: 3,
                failingCount: 0,
                pendingCount: 0,
                skippedCount: 0,
                failingChecks: []
            )
        )

        let model = OverviewViewModel(snapshots: [review, ready])
        let sectionsByCategory = Dictionary(uniqueKeysWithValues: model.pullRequestInboxSections.map { ($0.category, $0.items) })
        guard let reviewItem = sectionsByCategory[.review]?.first else {
            return XCTFail("Expected localized review item")
        }
        guard let readyItem = sectionsByCategory[.ready]?.first else {
            return XCTFail("Expected localized ready item")
        }

        XCTAssertEqual(reviewItem.reviewLine, "评审人：alex · 指派给：owner")
        XCTAssertEqual(reviewItem.actionLabel, "打开 PR")
        XCTAssertEqual(readyItem.detail, "3 个检查已通过 · 已获 sam 批准 · 已可加入合并队列并复制发布上下文")
        XCTAssertEqual(readyItem.statusBadge, "可发布")
    }

    func testWorktreeRowsSurfaceDirtyAndAheadWorktreesBeforeCleanOnes() {
        LocalizationManager.shared.updateSelectedLanguage(.english)

        let rootPath = "/tmp/repo"
        let featurePath = "/tmp/repo-feature"
        let cleanPath = "/tmp/repo-clean"
        let snapshot = OverviewWorkspaceSnapshot(
            id: UUID(),
            name: "Alpha",
            supportsRepositoryFeatures: true,
            activeWorktreePath: rootPath,
            hasUncommittedChanges: true,
            changedFileCount: 2,
            currentBranch: "main",
            activeSessionCount: 2,
            preferredWorkflow: nil,
            recentActivity: [],
            worktrees: [
                WorktreeModel(path: rootPath, branch: "main", head: "abc", isMainWorktree: true, isLocked: false, lockReason: nil),
                WorktreeModel(path: featurePath, branch: "feature/x", head: "def", isMainWorktree: false, isLocked: false, lockReason: nil),
                WorktreeModel(path: cleanPath, branch: "feature/y", head: "ghi", isMainWorktree: false, isLocked: false, lockReason: nil)
            ],
            worktreeStatuses: [
                rootPath: RepositoryStatusSnapshot(hasUncommittedChanges: true, changedFileCount: 2, aheadCount: 0, behindCount: 0, localBranches: [], remoteBranches: []),
                featurePath: RepositoryStatusSnapshot(hasUncommittedChanges: false, changedFileCount: 0, aheadCount: 3, behindCount: 1, localBranches: [], remoteBranches: []),
                cleanPath: RepositoryStatusSnapshot(hasUncommittedChanges: false, changedFileCount: 0, aheadCount: 0, behindCount: 0, localBranches: [], remoteBranches: [])
            ],
            gitHubStatuses: [:]
        )

        let model = OverviewViewModel(snapshots: [snapshot])

        XCTAssertEqual(model.worktreeRows.map(\.worktree.path), [rootPath, featurePath, cleanPath])
        XCTAssertEqual(model.worktreeRows[0].statusSummary, "2 changed")
        XCTAssertEqual(model.worktreeRows[1].statusSummary, "3 ahead · 1 behind")
        XCTAssertEqual(model.worktreeRows[2].statusSummary, "Clean and in sync")
    }
}

@MainActor
private func makeWorkspace(
    name: String,
    rootPath: String,
    pullRequest: GitHubPullRequestSummary?,
    checksSummary: GitHubPullRequestChecksSummary? = nil,
    changedFileCount: Int = 0,
    preferredWorkflow: WorkspaceWorkflow? = nil
) -> OverviewWorkspaceSnapshot {
    OverviewWorkspaceSnapshot(
        id: UUID(),
        name: name,
        supportsRepositoryFeatures: true,
        activeWorktreePath: rootPath,
        hasUncommittedChanges: changedFileCount > 0,
        changedFileCount: changedFileCount,
        currentBranch: "feature",
        activeSessionCount: 1,
        preferredWorkflow: preferredWorkflow,
        recentActivity: [],
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
        worktreeStatuses: [
            rootPath: RepositoryStatusSnapshot(
                hasUncommittedChanges: changedFileCount > 0,
                changedFileCount: changedFileCount,
                aheadCount: 0,
                behindCount: 0,
                localBranches: [],
                remoteBranches: []
            )
        ],
        gitHubStatuses: [
            rootPath: GitHubWorktreeStatus(
                pullRequest: pullRequest,
                checksSummary: checksSummary,
                latestRun: nil
            )
        ]
    )
}

private func makePullRequest(
    number: Int,
    title: String,
    mergeStateStatus: String,
    reviewDecision: String? = nil,
    reviewRequests: [String] = [],
    latestReviews: [(String, String)] = [],
    assignees: [String] = []
) -> GitHubPullRequestSummary {
    GitHubPullRequestSummary(
        number: number,
        title: title,
        url: "https://example.com/pr/\(number)",
        state: "OPEN",
        isDraft: false,
        headRefName: "feature-\(number)",
        mergeStateStatus: mergeStateStatus,
        reviewDecision: reviewDecision,
        reviewRequests: reviewRequests.map { GitHubPullRequestActor(login: $0) },
        latestReviews: latestReviews.map {
            GitHubPullRequestReviewSummary(
                author: GitHubPullRequestActor(login: $0.0),
                state: $0.1,
                submittedAt: nil
            )
        },
        assignees: assignees.map { GitHubPullRequestActor(login: $0) }
    )
}
