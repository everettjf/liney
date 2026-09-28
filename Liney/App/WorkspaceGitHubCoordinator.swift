//
//  WorkspaceGitHubCoordinator.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

@MainActor
private func githubL10n(_ key: String) -> String {
    LocalizationManager.shared.string(key)
}

@MainActor
private func githubL10nFormat(_ key: String, _ arguments: CVarArg...) -> String {
    l10nFormat(githubL10n(key), locale: Locale.current, arguments: arguments)
}

protocol GitHubCLIClient {
    func integrationState() async -> GitHubIntegrationState
    func status(repositoryRoot: String, branch: String) async throws -> GitHubWorktreeStatus
    func openPullRequest(repositoryRoot: String, number: Int) async throws
    func markPullRequestReady(repositoryRoot: String, number: Int) async throws
    func updatePullRequestBranch(repositoryRoot: String, number: Int) async throws
    func queuePullRequest(repositoryRoot: String, number: Int) async throws
    func releaseNoteDraft(repositoryRoot: String, number: Int) async throws -> String
    func openRun(repositoryRoot: String, runID: Int) async throws
    func rerunFailedJobs(repositoryRoot: String, runID: Int) async throws
    func latestRunLogs(repositoryRoot: String, runID: Int) async throws -> String
}

extension GitHubCLIService: GitHubCLIClient {}

struct WorkspaceGitHubStatusRefreshResult {
    let statuses: [String: GitHubWorktreeStatus]
    let integrationStateOverride: GitHubIntegrationState?
    let statusUpdate: WorkspaceCoordinatorStatusUpdate?
}

struct WorkspaceGitHubCommandResult {
    var sideEffects: [WorkspaceCoordinatorEffect]
    var activities: [WorkspaceCoordinatorActivityRecord]
    var statusUpdate: WorkspaceCoordinatorStatusUpdate?
    var workspaceIDsToRefresh: Set<UUID>
    var shouldPersist: Bool

    init(
        sideEffects: [WorkspaceCoordinatorEffect] = [],
        activities: [WorkspaceCoordinatorActivityRecord] = [],
        statusUpdate: WorkspaceCoordinatorStatusUpdate? = nil,
        workspaceIDsToRefresh: Set<UUID> = [],
        shouldPersist: Bool = false
    ) {
        self.sideEffects = sideEffects
        self.activities = activities
        self.statusUpdate = statusUpdate
        self.workspaceIDsToRefresh = workspaceIDsToRefresh
        self.shouldPersist = shouldPersist
    }
}

struct WorkspaceGitHubBatchRequest: Hashable {
    let workspace: WorkspaceModel
    let worktreePath: String

    static func == (lhs: WorkspaceGitHubBatchRequest, rhs: WorkspaceGitHubBatchRequest) -> Bool {
        lhs.workspace.id == rhs.workspace.id && lhs.worktreePath == rhs.worktreePath
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(workspace.id)
        hasher.combine(worktreePath)
    }
}

enum WorkspaceGitHubBatchAction {
    case updateBranch
    case queueMerge
    case copyReleaseContext
}

@MainActor
struct WorkspaceGitHubCoordinator {
    let client: any GitHubCLIClient

    func integrationState() async -> GitHubIntegrationState {
        await client.integrationState()
    }

    func refreshStatuses(
        for workspace: WorkspaceModel,
        integrationEnabled: Bool,
        currentIntegrationState: GitHubIntegrationState
    ) async -> WorkspaceGitHubStatusRefreshResult {
        guard workspace.supportsRepositoryFeatures else {
            return WorkspaceGitHubStatusRefreshResult(statuses: [:], integrationStateOverride: nil, statusUpdate: nil)
        }
        guard integrationEnabled else {
            return WorkspaceGitHubStatusRefreshResult(statuses: [:], integrationStateOverride: nil, statusUpdate: nil)
        }
        guard case .authorized = currentIntegrationState else {
            return WorkspaceGitHubStatusRefreshResult(statuses: workspace.gitHubStatuses, integrationStateOverride: nil, statusUpdate: nil)
        }

        var statuses = workspace.gitHubStatuses.filter { path, _ in
            workspace.worktrees.contains(where: { $0.path == path })
        }

        for worktree in workspace.worktrees {
            do {
                var status = try await client.status(repositoryRoot: workspace.repositoryRoot, branch: worktree.branch ?? "")
                status.refreshedAt = Date()
                status.refreshError = nil
                statuses[worktree.path] = status
            } catch GitHubCLIError.unauthorized {
                var stale = statuses[worktree.path] ?? GitHubWorktreeStatus()
                stale.refreshError = GitHubCLIError.unauthorized.localizedDescription
                statuses[worktree.path] = stale
                return WorkspaceGitHubStatusRefreshResult(
                    statuses: statuses,
                    integrationStateOverride: .unauthorized,
                    statusUpdate: WorkspaceCoordinatorStatusUpdate(
                        text: githubL10n("github.status.unauthenticated"),
                        tone: .warning
                    )
                )
            } catch {
                var stale = statuses[worktree.path] ?? GitHubWorktreeStatus()
                stale.refreshError = error.localizedDescription
                statuses[worktree.path] = stale
                continue
            }
        }

        return WorkspaceGitHubStatusRefreshResult(statuses: statuses, integrationStateOverride: nil, statusUpdate: nil)
    }

    func openPullRequest(workspace: WorkspaceModel, worktreePath: String) async throws -> WorkspaceGitHubCommandResult {
        guard let number = pullRequestNumber(in: workspace, worktreePath: worktreePath) else {
            return missingPullRequestResult()
        }
        try await client.openPullRequest(repositoryRoot: workspace.repositoryRoot, number: number)
        return WorkspaceGitHubCommandResult(
            activities: [
                activity(
                    workspaceID: workspace.id,
                    kind: .github,
                    title: githubL10n("github.activity.pullRequestOpened"),
                    detail: "#\(number) · \(worktreeDisplayName(in: workspace, path: worktreePath))",
                    worktreePath: worktreePath,
                    replayAction: .gitHub(.openPullRequest, worktreePath: worktreePath)
                )
            ]
        )
    }

    func markPullRequestReady(workspace: WorkspaceModel, worktreePath: String) async throws -> WorkspaceGitHubCommandResult {
        guard let number = pullRequestNumber(in: workspace, worktreePath: worktreePath) else {
            return missingPullRequestResult()
        }
        try await client.markPullRequestReady(repositoryRoot: workspace.repositoryRoot, number: number)
        return WorkspaceGitHubCommandResult(
            activities: [
                activity(
                    workspaceID: workspace.id,
                    kind: .github,
                    title: githubL10n("github.activity.pullRequestReady"),
                    detail: "#\(number) · \(worktreeDisplayName(in: workspace, path: worktreePath))",
                    worktreePath: worktreePath,
                    replayAction: .gitHub(.markPullRequestReady, worktreePath: worktreePath)
                )
            ],
            statusUpdate: WorkspaceCoordinatorStatusUpdate(text: githubL10n("github.status.pullRequestReady"), tone: .success),
            workspaceIDsToRefresh: [workspace.id],
            shouldPersist: true
        )
    }

    func updatePullRequestBranch(workspace: WorkspaceModel, worktreePath: String) async throws -> WorkspaceGitHubCommandResult {
        guard let number = pullRequestNumber(in: workspace, worktreePath: worktreePath) else {
            return missingPullRequestResult()
        }
        try await client.updatePullRequestBranch(repositoryRoot: workspace.repositoryRoot, number: number)
        return WorkspaceGitHubCommandResult(
            activities: [
                activity(
                    workspaceID: workspace.id,
                    kind: .github,
                    title: githubL10n("github.activity.pullRequestRebased"),
                    detail: "#\(number) · \(worktreeDisplayName(in: workspace, path: worktreePath))",
                    worktreePath: worktreePath,
                    replayAction: nil
                )
            ],
            statusUpdate: WorkspaceCoordinatorStatusUpdate(text: githubL10n("github.status.pullRequestRebaseRequested"), tone: .success),
            workspaceIDsToRefresh: [workspace.id],
            shouldPersist: true
        )
    }

    func queuePullRequest(workspace: WorkspaceModel, worktreePath: String) async throws -> WorkspaceGitHubCommandResult {
        guard let number = pullRequestNumber(in: workspace, worktreePath: worktreePath) else {
            return missingPullRequestResult()
        }
        try await client.queuePullRequest(repositoryRoot: workspace.repositoryRoot, number: number)
        return WorkspaceGitHubCommandResult(
            activities: [
                activity(
                    workspaceID: workspace.id,
                    kind: .github,
                    title: githubL10n("github.activity.pullRequestQueued"),
                    detail: "#\(number) · \(worktreeDisplayName(in: workspace, path: worktreePath))",
                    worktreePath: worktreePath,
                    replayAction: nil
                )
            ],
            statusUpdate: WorkspaceCoordinatorStatusUpdate(text: githubL10n("github.status.pullRequestQueued"), tone: .success),
            shouldPersist: true
        )
    }

    func copyPullRequestReleaseNotes(workspace: WorkspaceModel, worktreePath: String) async throws -> WorkspaceGitHubCommandResult {
        guard let number = pullRequestNumber(in: workspace, worktreePath: worktreePath) else {
            return missingPullRequestResult()
        }
        let draft = try await client.releaseNoteDraft(repositoryRoot: workspace.repositoryRoot, number: number)
        return WorkspaceGitHubCommandResult(
            sideEffects: [.copyText(draft)],
            activities: [
                activity(
                    workspaceID: workspace.id,
                    kind: .release,
                    title: githubL10n("github.activity.releaseContextGenerated"),
                    detail: githubL10nFormat("github.activity.releaseContextCopiedDetail", number),
                    worktreePath: worktreePath,
                    replayAction: nil
                )
            ],
            statusUpdate: WorkspaceCoordinatorStatusUpdate(text: githubL10n("github.status.releaseContextCopied"), tone: .success),
            shouldPersist: true
        )
    }

    func executeBatch(
        _ action: WorkspaceGitHubBatchAction,
        requests: [WorkspaceGitHubBatchRequest]
    ) async throws -> WorkspaceGitHubCommandResult {
        let normalizedRequests = Self.normalize(requests)
        guard !normalizedRequests.isEmpty else {
            return WorkspaceGitHubCommandResult(statusUpdate: WorkspaceCoordinatorStatusUpdate(text: emptyBatchMessage(for: action), tone: .warning))
        }
        let orderedRequests: [WorkspaceGitHubBatchRequest]
        switch action {
        case .copyReleaseContext:
            orderedRequests = normalizedRequests.sorted(by: Self.releaseContextSort)
        case .updateBranch, .queueMerge:
            orderedRequests = normalizedRequests
        }

        var succeeded = 0
        var failed = 0
        var refreshIDs = Set<UUID>()
        var activities: [WorkspaceCoordinatorActivityRecord] = []
        var drafts: [String] = []

        for request in orderedRequests {
            guard let number = pullRequestNumber(in: request.workspace, worktreePath: request.worktreePath) else {
                failed += 1
                continue
            }

            do {
                switch action {
                case .updateBranch:
                    try await client.updatePullRequestBranch(repositoryRoot: request.workspace.repositoryRoot, number: number)
                    activities.append(
                        activity(
                            workspaceID: request.workspace.id,
                            kind: .github,
                            title: githubL10n("github.activity.pullRequestRebased"),
                            detail: "#\(number) · \(worktreeDisplayName(in: request.workspace, path: request.worktreePath))",
                            worktreePath: request.worktreePath,
                            replayAction: nil
                        )
                    )
                    refreshIDs.insert(request.workspace.id)
                case .queueMerge:
                    try await client.queuePullRequest(repositoryRoot: request.workspace.repositoryRoot, number: number)
                    activities.append(
                        activity(
                            workspaceID: request.workspace.id,
                            kind: .github,
                            title: githubL10n("github.activity.pullRequestQueued"),
                            detail: "#\(number) · \(worktreeDisplayName(in: request.workspace, path: request.worktreePath))",
                            worktreePath: request.worktreePath,
                            replayAction: nil
                        )
                    )
                case .copyReleaseContext:
                    let draft = try await client.releaseNoteDraft(repositoryRoot: request.workspace.repositoryRoot, number: number)
                    drafts.append(["## \(request.workspace.name) · PR #\(number)", draft].joined(separator: "\n"))
                    activities.append(
                        activity(
                            workspaceID: request.workspace.id,
                            kind: .release,
                            title: githubL10n("github.activity.releaseContextGenerated"),
                            detail: githubL10nFormat("github.activity.batchReleaseContextIncludedDetail", number),
                            worktreePath: request.worktreePath,
                            replayAction: nil
                        )
                    )
                }
                succeeded += 1
            } catch {
                failed += 1
            }
        }

        var result = WorkspaceGitHubCommandResult(
            activities: activities,
            statusUpdate: WorkspaceCoordinatorStatusUpdate(
                text: batchSummary(action: action, success: succeeded, failed: failed),
                tone: failed > 0 ? .warning : .success
            ),
            workspaceIDsToRefresh: refreshIDs,
            shouldPersist: succeeded > 0
        )

        if action == .copyReleaseContext, !drafts.isEmpty {
            result.sideEffects.append(.copyText(drafts.joined(separator: "\n\n---\n\n")))
        } else if action == .copyReleaseContext, drafts.isEmpty {
            result.statusUpdate = WorkspaceCoordinatorStatusUpdate(
                text: githubL10n("github.status.batchReleaseContextFailed"),
                tone: .warning
            )
        }

        return result
    }

    func openLatestRun(workspace: WorkspaceModel, worktreePath: String) async throws -> WorkspaceGitHubCommandResult {
        guard let latestRun = workspace.gitHubStatus(for: worktreePath)?.latestRun else {
            return WorkspaceGitHubCommandResult(statusUpdate: WorkspaceCoordinatorStatusUpdate(text: githubL10n("github.status.noCIRun"), tone: .warning))
        }
        try await client.openRun(repositoryRoot: workspace.repositoryRoot, runID: latestRun.id)
        return WorkspaceGitHubCommandResult(
            activities: [
                activity(
                    workspaceID: workspace.id,
                    kind: .github,
                    title: githubL10n("github.activity.latestCIRunOpened"),
                    detail: worktreeDisplayName(in: workspace, path: worktreePath),
                    worktreePath: worktreePath,
                    replayAction: .gitHub(.openLatestRun, worktreePath: worktreePath)
                )
            ]
        )
    }

    func openFailingCheckDetails(workspace: WorkspaceModel, worktreePath: String) -> WorkspaceGitHubCommandResult {
        guard let urlString = workspace.gitHubStatus(for: worktreePath)?.checksSummary?.failingChecks.first?.link,
              let url = URL(string: urlString) else {
            return WorkspaceGitHubCommandResult(statusUpdate: WorkspaceCoordinatorStatusUpdate(text: githubL10n("github.status.noFailingCheckDetails"), tone: .warning))
        }
        return WorkspaceGitHubCommandResult(sideEffects: [.openURL(url)])
    }

    func copyFailingCheckURL(workspace: WorkspaceModel, worktreePath: String) -> WorkspaceGitHubCommandResult {
        guard let urlString = workspace.gitHubStatus(for: worktreePath)?.checksSummary?.failingChecks.first?.link else {
            return WorkspaceGitHubCommandResult(statusUpdate: WorkspaceCoordinatorStatusUpdate(text: githubL10n("github.status.noFailingCheckURL"), tone: .warning))
        }
        return WorkspaceGitHubCommandResult(
            sideEffects: [.copyText(urlString)],
            statusUpdate: WorkspaceCoordinatorStatusUpdate(text: githubL10n("github.status.failingCheckURLCopied"), tone: .success)
        )
    }

    func rerunLatestFailedJobs(workspace: WorkspaceModel, worktreePath: String) async throws -> WorkspaceGitHubCommandResult {
        guard let latestRun = workspace.gitHubStatus(for: worktreePath)?.latestRun else {
            return WorkspaceGitHubCommandResult(statusUpdate: WorkspaceCoordinatorStatusUpdate(text: githubL10n("github.status.noCIRun"), tone: .warning))
        }
        guard latestRun.isFailing else {
            return WorkspaceGitHubCommandResult(statusUpdate: WorkspaceCoordinatorStatusUpdate(text: githubL10n("github.status.latestCIRunNotFailing"), tone: .neutral))
        }
        try await client.rerunFailedJobs(repositoryRoot: workspace.repositoryRoot, runID: latestRun.id)
        return WorkspaceGitHubCommandResult(
            statusUpdate: WorkspaceCoordinatorStatusUpdate(text: githubL10n("github.status.rerunRequested"), tone: .success)
        )
    }

    func copyLatestRunLogs(workspace: WorkspaceModel, worktreePath: String) async throws -> WorkspaceGitHubCommandResult {
        guard let latestRun = workspace.gitHubStatus(for: worktreePath)?.latestRun else {
            return WorkspaceGitHubCommandResult(statusUpdate: WorkspaceCoordinatorStatusUpdate(text: githubL10n("github.status.noCIRun"), tone: .warning))
        }
        let logs = try await client.latestRunLogs(repositoryRoot: workspace.repositoryRoot, runID: latestRun.id)
        return WorkspaceGitHubCommandResult(
            sideEffects: [.copyText(logs)],
            statusUpdate: WorkspaceCoordinatorStatusUpdate(text: githubL10n("github.status.latestCILogsCopied"), tone: .success)
        )
    }

    private func pullRequestNumber(in workspace: WorkspaceModel, worktreePath: String) -> Int? {
        workspace.gitHubStatus(for: worktreePath)?.pullRequest?.number
    }

    private func worktreeDisplayName(in workspace: WorkspaceModel, path: String) -> String {
        workspace.worktrees.first(where: { $0.path == path })?.displayName ?? URL(fileURLWithPath: path).lastPathComponent
    }

    private func missingPullRequestResult() -> WorkspaceGitHubCommandResult {
        WorkspaceGitHubCommandResult(statusUpdate: WorkspaceCoordinatorStatusUpdate(text: githubL10n("github.status.noPullRequest"), tone: .warning))
    }

    private func activity(
        workspaceID: UUID,
        kind: WorkspaceActivityKind,
        title: String,
        detail: String,
        worktreePath: String?,
        replayAction: WorkspaceReplayAction?
    ) -> WorkspaceCoordinatorActivityRecord {
        WorkspaceCoordinatorActivityRecord(
            workspaceID: workspaceID,
            kind: kind,
            title: title,
            detail: detail,
            worktreePath: worktreePath,
            replayAction: replayAction
        )
    }

    private func emptyBatchMessage(for action: WorkspaceGitHubBatchAction) -> String {
        switch action {
        case .updateBranch:
            return githubL10n("github.status.batchEmpty.updateBranch")
        case .queueMerge:
            return githubL10n("github.status.batchEmpty.queueMerge")
        case .copyReleaseContext:
            return githubL10n("github.status.batchEmpty.releaseContext")
        }
    }

    private func batchSummary(action: WorkspaceGitHubBatchAction, success: Int, failed: Int) -> String {
        let successMessage: String
        switch action {
        case .updateBranch:
            successMessage = githubL10n("github.status.batchSummary.updateBranch")
        case .queueMerge:
            successMessage = githubL10n("github.status.batchSummary.queueMerge")
        case .copyReleaseContext:
            successMessage = githubL10n("github.status.batchSummary.releaseContext")
        }

        if success == 0, failed > 0 {
            return githubL10nFormat("github.status.batchSummary.failedFormat", failed)
        }
        if failed > 0 {
            return githubL10nFormat("github.status.batchSummary.partialFormat", successMessage, success, failed)
        }
        return githubL10nFormat("github.status.batchSummary.totalFormat", successMessage, success)
    }

    private static func normalize(_ requests: [WorkspaceGitHubBatchRequest]) -> [WorkspaceGitHubBatchRequest] {
        var seen = Set<WorkspaceGitHubBatchRequest>()
        var result: [WorkspaceGitHubBatchRequest] = []
        for request in requests where seen.insert(request).inserted {
            result.append(request)
        }
        return result
    }

    private static func releaseContextSort(lhs: WorkspaceGitHubBatchRequest, rhs: WorkspaceGitHubBatchRequest) -> Bool {
        let nameComparison = lhs.workspace.name.localizedCaseInsensitiveCompare(rhs.workspace.name)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }
        if lhs.workspace.repositoryRoot != rhs.workspace.repositoryRoot {
            return lhs.workspace.repositoryRoot < rhs.workspace.repositoryRoot
        }
        return lhs.worktreePath < rhs.worktreePath
    }
}
