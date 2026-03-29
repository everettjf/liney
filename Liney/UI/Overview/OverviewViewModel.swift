//
//  OverviewViewModel.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

private func overviewLocalized(_ key: String) -> String {
    LocalizationManager.shared.string(key)
}

private func overviewLocalizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    l10nFormat(overviewLocalized(key), locale: Locale.current, arguments: arguments)
}

@MainActor
struct OverviewWorkspaceSnapshot: Identifiable {
    let id: UUID
    let name: String
    let supportsRepositoryFeatures: Bool
    let activeWorktreePath: String
    let hasUncommittedChanges: Bool
    let changedFileCount: Int
    let currentBranch: String
    let activeSessionCount: Int
    let preferredWorkflow: WorkspaceWorkflow?
    let recentActivity: [WorkspaceActivityEntry]
    let worktrees: [WorktreeModel]
    let worktreeStatuses: [String: RepositoryStatusSnapshot]
    let gitHubStatuses: [String: GitHubWorktreeStatus]

    init(
        id: UUID,
        name: String,
        supportsRepositoryFeatures: Bool,
        activeWorktreePath: String,
        hasUncommittedChanges: Bool,
        changedFileCount: Int,
        currentBranch: String,
        activeSessionCount: Int,
        preferredWorkflow: WorkspaceWorkflow?,
        recentActivity: [WorkspaceActivityEntry],
        worktrees: [WorktreeModel],
        worktreeStatuses: [String: RepositoryStatusSnapshot],
        gitHubStatuses: [String: GitHubWorktreeStatus]
    ) {
        self.id = id
        self.name = name
        self.supportsRepositoryFeatures = supportsRepositoryFeatures
        self.activeWorktreePath = activeWorktreePath
        self.hasUncommittedChanges = hasUncommittedChanges
        self.changedFileCount = changedFileCount
        self.currentBranch = currentBranch
        self.activeSessionCount = activeSessionCount
        self.preferredWorkflow = preferredWorkflow
        self.recentActivity = recentActivity
        self.worktrees = worktrees
        self.worktreeStatuses = worktreeStatuses
        self.gitHubStatuses = gitHubStatuses
    }

    init(workspace: WorkspaceModel) {
        self.init(
            id: workspace.id,
            name: workspace.name,
            supportsRepositoryFeatures: workspace.supportsRepositoryFeatures,
            activeWorktreePath: workspace.activeWorktreePath,
            hasUncommittedChanges: workspace.hasUncommittedChanges,
            changedFileCount: workspace.changedFileCount,
            currentBranch: workspace.currentBranch,
            activeSessionCount: workspace.activeSessionCount,
            preferredWorkflow: workspace.preferredWorkflow,
            recentActivity: workspace.activityLog,
            worktrees: workspace.worktrees,
            worktreeStatuses: workspace.worktreeStatuses,
            gitHubStatuses: workspace.gitHubStatuses
        )
    }

    func gitHubStatus(for worktreePath: String) -> GitHubWorktreeStatus? {
        gitHubStatuses[worktreePath]
    }
}

@MainActor
struct OverviewViewModel {
    let workspaces: [OverviewWorkspaceSnapshot]

    init(workspaces: [WorkspaceModel]) {
        self.workspaces = workspaces.map(OverviewWorkspaceSnapshot.init)
    }

    init(snapshots: [OverviewWorkspaceSnapshot]) {
        self.workspaces = snapshots
    }

    var totalWorkspaces: Int {
        workspaces.count
    }

    var totalSessions: Int {
        workspaces.reduce(0) { $0 + $1.activeSessionCount }
    }

    var dirtyRepositories: Int {
        dirtyWorkspaceRows.count
    }

    var failingPullRequests: Int {
        failingWorkspaces.count
    }

    var dirtyWorkspaceRows: [OverviewWorkspaceSnapshot] {
        workspaces.filter { $0.supportsRepositoryFeatures && $0.hasUncommittedChanges }
    }

    var workflowLaunchers: [OverviewWorkflowLauncher] {
        workspaces.compactMap { workspace in
            guard let workflow = workspace.preferredWorkflow else { return nil }
            return OverviewWorkflowLauncher(
                workspaceID: workspace.id,
                workspaceName: workspace.name,
                workflowID: workflow.id,
                workflowName: workflow.name
            )
        }
    }

    var recentActivities: [OverviewTimelineItem] {
        workspaces
            .flatMap { workspace in
                workspace.recentActivity.map { OverviewTimelineItem(workspace: workspace, entry: $0) }
            }
            .filter { $0.entry.kind != .release }
            .sorted { $0.entry.timestamp > $1.entry.timestamp }
            .prefix(12)
            .map { $0 }
    }

    var worktreeRows: [OverviewWorktreeRow] {
        workspaces
            .filter(\.supportsRepositoryFeatures)
            .flatMap { workspace in
                workspace.worktrees.map { worktree in
                    OverviewWorktreeRow(
                        workspace: workspace,
                        worktree: worktree,
                        status: workspace.worktreeStatuses[worktree.path],
                        isActive: workspace.activeWorktreePath == worktree.path
                    )
                }
            }
            .sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive {
                    return lhs.isActive && !rhs.isActive
                }
                if lhs.sortPriority != rhs.sortPriority {
                    return lhs.sortPriority > rhs.sortPriority
                }
                if lhs.workspace.name != rhs.workspace.name {
                    return lhs.workspace.name.localizedCaseInsensitiveCompare(rhs.workspace.name) == .orderedAscending
                }
                return lhs.worktree.displayName.localizedCaseInsensitiveCompare(rhs.worktree.displayName) == .orderedAscending
            }
    }

    var executionCards: [OverviewTaskCard] {
        var cards = failingWorkspaces.map {
            OverviewTaskCard(
                id: "execute:failing:\($0.id)",
                workspace: $0.workspace,
                title: $0.workspace.name,
                subtitle: "\($0.worktree.displayName) · \($0.failingCount) failing check(s)",
                detail: $0.firstFailingCheckName ?? overviewLocalized("overview.model.openFirstFailingCheck"),
                actionLabel: overviewLocalized("overview.model.openCheck"),
                action: .openFailingCheck($0.workspace.id, $0.worktree.path)
            )
        }

        cards.append(contentsOf: workflowLaunchers.compactMap { launcher in
            guard let workspace = workspace(id: launcher.workspaceID) else { return nil }
            return OverviewTaskCard(
                id: "execute:workflow:\(launcher.id)",
                workspace: workspace,
                title: launcher.workspaceName,
                subtitle: overviewLocalized("overview.model.preferredWorkflow"),
                detail: launcher.workflowName,
                actionLabel: overviewLocalized("overview.model.runWorkflow"),
                action: .runWorkflow(launcher.workspaceID, launcher.workflowID)
            )
        })

        cards.append(contentsOf: dirtyWorkspaceRows.map {
            OverviewTaskCard(
                id: "execute:dirty:\($0.id.uuidString)",
                workspace: $0,
                title: $0.name,
                subtitle: overviewLocalizedFormat("overview.model.changedFilesFormat", $0.changedFileCount),
                detail: $0.currentBranch,
                actionLabel: overviewLocalized("overview.model.openWorkspace"),
                action: .openWorkspace($0.id)
            )
        })

        return cards
    }

    var waitingCards: [OverviewTaskCard] {
        blockedWorkspaces.map { item in
            OverviewTaskCard(
                id: "waiting:\(item.id)",
                workspace: item.workspace,
                title: item.workspace.name,
                subtitle: "#\(item.number) · \(item.worktree.displayName)",
                detail: item.readinessDetail,
                actionLabel: item.primaryActionLabel,
                action: item.primaryAction
            )
        }
    }

    var shippingCards: [OverviewTaskCard] {
        readyToMergeWorkspaces.map {
            OverviewTaskCard(
                id: "shipping:\($0.id)",
                workspace: $0.workspace,
                title: $0.workspace.name,
                subtitle: "#\($0.number) · \($0.worktree.displayName)",
                detail: $0.detail,
                actionLabel: overviewLocalized("overview.model.queueMerge"),
                action: .queuePullRequest($0.workspace.id, $0.worktree.path)
            )
        }
    }

    var todayFocusItems: [OverviewFocusItem] {
        let failingCandidates = failingWorkspaces.map {
            OverviewFocusItem(
                id: "focus:failing:\($0.id)",
                workspace: $0.workspace,
                priority: 0,
                headline: overviewLocalized("overview.model.fixFailingChecks"),
                detail: overviewLocalizedFormat("overview.model.fixFailingChecksDetailFormat", $0.workspace.name, $0.worktree.displayName, $0.failingCount),
                actionLabel: overviewLocalized("overview.model.openCheck"),
                action: .openFailingCheck($0.workspace.id, $0.worktree.path)
            )
        }

        let readyCandidates = readyToMergeWorkspaces.map {
            OverviewFocusItem(
                id: "focus:ready:\($0.id)",
                workspace: $0.workspace,
                priority: 1,
                headline: overviewLocalized("overview.model.shipMergeReadyPR"),
                detail: "\($0.workspace.name) · #\($0.number) · \($0.title)",
                actionLabel: overviewLocalized("overview.model.queueMerge"),
                action: .queuePullRequest($0.workspace.id, $0.worktree.path)
            )
        }

        let blockedCandidates = blockedWorkspaces.map {
            OverviewFocusItem(
                id: "focus:blocked:\($0.id)",
                workspace: $0.workspace,
                priority: 2,
                headline: $0.focusHeadline,
                detail: "\($0.workspace.name) · #\($0.number) · \($0.worktree.displayName)",
                actionLabel: $0.primaryActionLabel,
                action: $0.primaryAction
            )
        }

        let workflowCandidates = workflowLaunchers.compactMap { launcher -> OverviewFocusItem? in
            guard let workspace = workspace(id: launcher.workspaceID) else { return nil }
            return OverviewFocusItem(
                id: "focus:workflow:\(launcher.id)",
                workspace: workspace,
                priority: 3,
                headline: overviewLocalized("overview.model.runPreferredWorkflow"),
                detail: "\(launcher.workspaceName) · \(launcher.workflowName)",
                actionLabel: overviewLocalized("overview.model.runWorkflow"),
                action: .runWorkflow(launcher.workspaceID, launcher.workflowID)
            )
        }

        let dirtyCandidates = dirtyWorkspaceRows.map {
            OverviewFocusItem(
                id: "focus:dirty:\($0.id.uuidString)",
                workspace: $0,
                priority: 4,
                headline: overviewLocalized("overview.model.reviewLocalChanges"),
                detail: overviewLocalizedFormat("overview.model.reviewLocalChangesDetailFormat", $0.name, $0.changedFileCount, $0.currentBranch),
                actionLabel: overviewLocalized("overview.model.openWorkspace"),
                action: .openWorkspace($0.id)
            )
        }

        let candidates = failingCandidates + readyCandidates + blockedCandidates + workflowCandidates + dirtyCandidates
        let sorted = candidates.sorted {
            if $0.priority != $1.priority {
                return $0.priority < $1.priority
            }
            return $0.workspace.name.localizedCaseInsensitiveCompare($1.workspace.name) == .orderedAscending
        }

        var seenWorkspaceIDs = Set<UUID>()
        var result: [OverviewFocusItem] = []
        for candidate in sorted where seenWorkspaceIDs.insert(candidate.workspace.id).inserted {
            result.append(candidate)
            if result.count == 5 {
                break
            }
        }
        return result
    }

    var blockerGroups: [OverviewBlockerGroup] {
        var groups: [OverviewBlockerGroup] = []

        if !failingWorkspaces.isEmpty {
            groups.append(
                OverviewBlockerGroup(
                    id: "blocker:failing",
                    style: .failingChecks,
                    title: overviewLocalized("overview.model.failingChecks"),
                    count: failingWorkspaces.count,
                    items: failingWorkspaces.map {
                        OverviewBlockerItem(
                            id: "blocker:failing:\($0.id)",
                            workspace: $0.workspace,
                            title: $0.workspace.name,
                            subtitle: "\($0.worktree.displayName) · \($0.failingCount) failing",
                            detail: $0.firstFailingCheckName ?? overviewLocalized("overview.model.openFailingCheck"),
                            actionLabel: overviewLocalized("overview.model.openCheck"),
                            action: .openFailingCheck($0.workspace.id, $0.worktree.path)
                        )
                    }
                )
            )
        }

        for readiness in [GitHubMergeReadiness.behind, .changesRequested, .conflicted, .blocked, .draft] {
            let matches = blockedWorkspaces.filter { $0.readiness == readiness }
            guard !matches.isEmpty else { continue }
            groups.append(
                OverviewBlockerGroup(
                    id: "blocker:\(readiness.rawValue)",
                    style: .mergeReadiness(readiness),
                    title: readiness.blockerTitle,
                    count: matches.count,
                    items: matches.map {
                        OverviewBlockerItem(
                            id: "blocker:\(readiness.rawValue):\($0.id)",
                            workspace: $0.workspace,
                            title: $0.workspace.name,
                            subtitle: "#\($0.number) · \($0.worktree.displayName)",
                            detail: $0.title,
                            actionLabel: $0.primaryActionLabel,
                            action: $0.primaryAction
                        )
                    }
                )
            )
        }

        return groups
    }

    var pullRequestInboxSections: [OverviewPullRequestInboxSection] {
        OverviewPullRequestInboxCategory.allCases.compactMap { category in
            let items = pullRequestInboxItems.filter { $0.category == category }
            guard !items.isEmpty else { return nil }
            return OverviewPullRequestInboxSection(category: category, items: items)
        }
    }

    var readyPullRequestTargets: [WorkspaceGitHubTarget] {
        pullRequestInboxItems.filter { $0.category == .ready }.map(\.target)
    }

    var behindPullRequestTargets: [WorkspaceGitHubTarget] {
        pullRequestInboxItems.filter { $0.category == .behind }.map(\.target)
    }

    var releaseContextTargets: [WorkspaceGitHubTarget] {
        readyPullRequestTargets
    }

    private var failingWorkspaces: [OverviewFailingWorkspace] {
        workspaces.compactMap { workspace in
            workspace.worktrees.compactMap { worktree -> OverviewFailingWorkspace? in
                guard let status = workspace.gitHubStatus(for: worktree.path),
                      let checks = status.checksSummary,
                      checks.failingCount > 0 else {
                    return nil
                }
                return OverviewFailingWorkspace(
                    workspace: workspace,
                    worktree: worktree,
                    failingCount: checks.failingCount,
                    firstFailingCheckName: checks.failingChecks.first?.name
                )
            }.first
        }
    }

    private var readyToMergeWorkspaces: [OverviewReadyWorkspace] {
        workspaces.compactMap { workspace in
            workspace.worktrees.compactMap { worktree -> OverviewReadyWorkspace? in
                guard let status = workspace.gitHubStatus(for: worktree.path),
                      let pullRequest = status.pullRequest,
                      pullRequest.isOpen,
                      pullRequest.mergeReadiness == .ready,
                      pullRequest.requestedReviewerLogins.isEmpty else {
                    return nil
                }
                return OverviewReadyWorkspace(
                    workspace: workspace,
                    worktree: worktree,
                    number: pullRequest.number,
                    title: pullRequest.title,
                    detail: pullRequestContextLine(pullRequest: pullRequest, checksSummary: status.checksSummary, latestRun: status.latestRun)
                )
            }.first
        }
    }

    private var blockedWorkspaces: [OverviewBlockedWorkspace] {
        workspaces.flatMap { workspace in
            workspace.worktrees.compactMap { worktree -> OverviewBlockedWorkspace? in
                guard let status = workspace.gitHubStatus(for: worktree.path),
                      let pullRequest = status.pullRequest,
                      pullRequest.isOpen else {
                    return nil
                }

                let shouldTreatAsReview = pullRequest.mergeReadiness == .ready && pullRequest.needsReviewerAttention
                let blockedStates: Set<GitHubMergeReadiness> = [.behind, .changesRequested, .conflicted, .blocked, .draft]
                guard blockedStates.contains(pullRequest.mergeReadiness) || shouldTreatAsReview else {
                    return nil
                }

                return OverviewBlockedWorkspace(
                    workspace: workspace,
                    worktree: worktree,
                    number: pullRequest.number,
                    title: pullRequest.title,
                    readiness: shouldTreatAsReview ? .checking : pullRequest.mergeReadiness,
                    requestedReviewerLogins: pullRequest.requestedReviewerLogins,
                    changesRequestedByLogins: pullRequest.changesRequestedByLogins,
                    checksSummary: status.checksSummary
                )
            }
        }
    }

    private var pullRequestInboxItems: [OverviewPullRequestInboxItem] {
        workspaces
            .flatMap { workspace in
                workspace.worktrees.compactMap { worktree in
                    guard let status = workspace.gitHubStatus(for: worktree.path),
                          let pullRequest = status.pullRequest,
                          pullRequest.isOpen else {
                        return nil
                    }
                    return OverviewPullRequestInboxItem(
                        workspace: workspace,
                        worktree: worktree,
                        pullRequest: pullRequest,
                        checksSummary: status.checksSummary,
                        latestRun: status.latestRun
                    )
                }
            }
            .sorted { lhs, rhs in
                if lhs.category.sortOrder != rhs.category.sortOrder {
                    return lhs.category.sortOrder < rhs.category.sortOrder
                }
                return lhs.workspace.name.localizedCaseInsensitiveCompare(rhs.workspace.name) == .orderedAscending
            }
    }

    private func workspace(id: UUID) -> OverviewWorkspaceSnapshot? {
        workspaces.first(where: { $0.id == id })
    }

    private func pullRequestContextLine(
        pullRequest: GitHubPullRequestSummary,
        checksSummary: GitHubPullRequestChecksSummary?,
        latestRun: GitHubWorkflowRunSummary?
    ) -> String {
        let reviewLine = reviewSummary(for: pullRequest)
        let checkLine = checkSummaryLine(checksSummary: checksSummary, latestRun: latestRun)
        let combined = [reviewLine, checkLine].compactMap { $0 }.joined(separator: " · ")
        return combined.nilIfEmpty ?? pullRequest.title
    }

    private func reviewSummary(for pullRequest: GitHubPullRequestSummary) -> String? {
        if !pullRequest.changesRequestedByLogins.isEmpty {
            return overviewLocalizedFormat("overview.model.changesRequestedByFormat", pullRequest.changesRequestedByLogins.joined(separator: ", "))
        }
        if !pullRequest.requestedReviewerLogins.isEmpty {
            return overviewLocalizedFormat("overview.model.waitingOnFormat", pullRequest.requestedReviewerLogins.joined(separator: ", "))
        }
        if !pullRequest.approvedByLogins.isEmpty {
            return overviewLocalizedFormat("overview.model.approvedByFormat", pullRequest.approvedByLogins.joined(separator: ", "))
        }
        if !pullRequest.assigneeLogins.isEmpty {
            return overviewLocalizedFormat("overview.model.assignedToFormat", pullRequest.assigneeLogins.joined(separator: ", "))
        }
        return nil
    }

    private func checkSummaryLine(
        checksSummary: GitHubPullRequestChecksSummary?,
        latestRun: GitHubWorkflowRunSummary?
    ) -> String? {
        guard let checksSummary else {
            return latestRun?.title.nilIfEmpty
        }
        if checksSummary.failingCount > 0 {
            return checksSummary.failingChecks.first?.name ?? overviewLocalizedFormat("overview.model.failingChecksCountFormat", checksSummary.failingCount)
        }
        if checksSummary.pendingCount > 0 {
            return overviewLocalizedFormat("overview.model.pendingChecksFormat", checksSummary.pendingCount)
        }
        if checksSummary.passingCount > 0 {
            return overviewLocalizedFormat("overview.model.passingChecksFormat", checksSummary.passingCount)
        }
        return latestRun?.title.nilIfEmpty
    }
}

enum OverviewWorkspaceAction {
    case openWorkspace(UUID)
    case runWorkflow(UUID, UUID)
    case openFailingCheck(UUID, String)
    case queuePullRequest(UUID, String)
    case updatePullRequestBranch(UUID, String)
    case openPullRequest(UUID, String)
    case queuePullRequests([WorkspaceGitHubTarget])
    case updatePullRequestBranches([WorkspaceGitHubTarget])
    case copyPullRequestReleaseNotesBatch([WorkspaceGitHubTarget])
}

struct OverviewWorkflowLauncher: Identifiable {
    let workspaceID: UUID
    let workspaceName: String
    let workflowID: UUID
    let workflowName: String

    var id: String {
        "\(workspaceID.uuidString):\(workflowID.uuidString)"
    }
}

struct OverviewWorktreeRow: Identifiable {
    let workspace: OverviewWorkspaceSnapshot
    let worktree: WorktreeModel
    let status: RepositoryStatusSnapshot?
    let isActive: Bool

    var id: String {
        "\(workspace.id.uuidString):\(worktree.path)"
    }

    var sortPriority: Int {
        var score = 0
        if status?.hasUncommittedChanges == true { score += 3 }
        if (status?.aheadCount ?? 0) > 0 { score += 2 }
        if (status?.behindCount ?? 0) > 0 { score += 1 }
        return score
    }

    var statusSummary: String {
        let changed = status?.changedFileCount ?? 0
        let ahead = status?.aheadCount ?? 0
        let behind = status?.behindCount ?? 0

        var parts: [String] = []
        if changed > 0 {
            parts.append(overviewLocalizedFormat("overview.worktrees.changedFormat", changed))
        }
        if ahead > 0 {
            parts.append(overviewLocalizedFormat("overview.worktrees.aheadFormat", ahead))
        }
        if behind > 0 {
            parts.append(overviewLocalizedFormat("overview.worktrees.behindFormat", behind))
        }
        if parts.isEmpty {
            return overviewLocalized("overview.worktrees.clean")
        }
        return parts.joined(separator: " · ")
    }
}

struct OverviewTimelineItem: Identifiable {
    let workspace: OverviewWorkspaceSnapshot
    let entry: WorkspaceActivityEntry

    var id: UUID { entry.id }

    var worktreeName: String? {
        guard let path = entry.worktreePath else { return nil }
        return workspace.worktrees.first(where: { $0.path == path })?.displayName ?? URL(fileURLWithPath: path).lastPathComponent
    }
}

struct OverviewTaskCard: Identifiable {
    let id: String
    let workspace: OverviewWorkspaceSnapshot
    let title: String
    let subtitle: String
    let detail: String
    let actionLabel: String
    let action: OverviewWorkspaceAction
}

struct OverviewFocusItem: Identifiable {
    let id: String
    let workspace: OverviewWorkspaceSnapshot
    let priority: Int
    let headline: String
    let detail: String
    let actionLabel: String
    let action: OverviewWorkspaceAction
}

enum OverviewBlockerGroupStyle: Hashable {
    case failingChecks
    case mergeReadiness(GitHubMergeReadiness)
}

struct OverviewBlockerGroup: Identifiable {
    let id: String
    let style: OverviewBlockerGroupStyle
    let title: String
    let count: Int
    let items: [OverviewBlockerItem]
}

struct OverviewBlockerItem: Identifiable {
    let id: String
    let workspace: OverviewWorkspaceSnapshot
    let title: String
    let subtitle: String
    let detail: String
    let actionLabel: String
    let action: OverviewWorkspaceAction
}

struct OverviewPullRequestInboxSection: Identifiable {
    let category: OverviewPullRequestInboxCategory
    let items: [OverviewPullRequestInboxItem]

    var id: String { category.rawValue }
}

enum OverviewPullRequestInboxCategory: String, CaseIterable {
    case failing
    case behind
    case review
    case ready

    var sortOrder: Int {
        switch self {
        case .failing:
            return 0
        case .behind:
            return 1
        case .review:
            return 2
        case .ready:
            return 3
        }
    }

    var title: String {
        switch self {
        case .failing:
            return overviewLocalized("overview.inbox.category.failing")
        case .behind:
            return overviewLocalized("overview.inbox.category.behind")
        case .review:
            return overviewLocalized("overview.inbox.category.review")
        case .ready:
            return overviewLocalized("overview.inbox.category.ready")
        }
    }

    var systemName: String {
        switch self {
        case .failing:
            return "exclamationmark.triangle.fill"
        case .behind:
            return "arrow.trianglehead.clockwise"
        case .review:
            return "text.bubble"
        case .ready:
            return "paperplane.fill"
        }
    }
}

struct OverviewPullRequestInboxItem: Identifiable {
    let workspace: OverviewWorkspaceSnapshot
    let worktree: WorktreeModel
    let pullRequest: GitHubPullRequestSummary
    let checksSummary: GitHubPullRequestChecksSummary?
    let latestRun: GitHubWorkflowRunSummary?

    var id: String {
        "\(workspace.id.uuidString):pr-inbox:\(worktree.path)"
    }

    var target: WorkspaceGitHubTarget {
        WorkspaceGitHubTarget(workspaceID: workspace.id, worktreePath: worktree.path)
    }

    var category: OverviewPullRequestInboxCategory {
        if (checksSummary?.failingCount ?? 0) > 0 {
            return .failing
        }
        if pullRequest.mergeReadiness == .behind {
            return .behind
        }
        if pullRequest.mergeReadiness == .ready && pullRequest.requestedReviewerLogins.isEmpty {
            return .ready
        }
        return .review
    }

    var subtitle: String {
        "#\(pullRequest.number) · \(worktree.displayName)"
    }

    var detail: String {
        switch category {
        case .failing:
            if let first = checksSummary?.failingChecks.first?.name {
                return overviewLocalizedFormat("overview.inbox.detail.failingPrefixFormat", first)
            }
            return overviewLocalized("overview.inbox.detail.fixFailingBeforeMerge")
        case .behind:
            return detailParts([
                overviewLocalized("overview.inbox.detail.behindBaseBranch"),
                reviewStatus
            ], fallback: overviewLocalized("overview.inbox.detail.behindFallback"))
        case .review:
            return detailParts([
                reviewStatus,
                checkStatus,
                pullRequest.title
            ], fallback: overviewLocalized("overview.inbox.detail.reviewFallback"))
        case .ready:
            return detailParts([
                checkStatus,
                reviewStatus,
                overviewLocalized("overview.inbox.detail.readyForMergeQueue")
            ], fallback: overviewLocalized("overview.inbox.detail.readyForMergeQueue"))
        }
    }

    var reviewLine: String? {
        detailParts([
            !pullRequest.requestedReviewerLogins.isEmpty ? overviewLocalizedFormat("overview.inbox.review.reviewersFormat", pullRequest.requestedReviewerLogins.joined(separator: ", ")) : nil,
            !pullRequest.changesRequestedByLogins.isEmpty ? overviewLocalizedFormat("overview.inbox.review.changesFormat", pullRequest.changesRequestedByLogins.joined(separator: ", ")) : nil,
            !pullRequest.assigneeLogins.isEmpty ? overviewLocalizedFormat("overview.inbox.review.assigneesFormat", pullRequest.assigneeLogins.joined(separator: ", ")) : nil,
            !pullRequest.approvedByLogins.isEmpty ? overviewLocalizedFormat("overview.inbox.review.approvedFormat", pullRequest.approvedByLogins.joined(separator: ", ")) : nil
        ], fallback: nil)
    }

    var statusBadge: String {
        switch category {
        case .failing:
            return overviewLocalizedFormat("overview.inbox.status.failFormat", checksSummary?.failingCount ?? 0)
        case .behind:
            return overviewLocalized("overview.inbox.status.behind")
        case .review:
            if !pullRequest.changesRequestedByLogins.isEmpty {
                return overviewLocalized("overview.inbox.status.changes")
            }
            if !pullRequest.requestedReviewerLogins.isEmpty {
                return overviewLocalized("overview.inbox.status.review")
            }
            return pullRequest.mergeReadiness.label.uppercased()
        case .ready:
            return overviewLocalized("overview.inbox.status.ready")
        }
    }

    var actionLabel: String {
        switch category {
        case .failing:
            return overviewLocalized("overview.model.openCheck")
        case .behind:
            return overviewLocalized("overview.inbox.action.update")
        case .review:
            return overviewLocalized("overview.inbox.action.openPR")
        case .ready:
            return overviewLocalized("overview.model.queueMerge")
        }
    }

    var action: OverviewWorkspaceAction {
        switch category {
        case .failing:
            return .openFailingCheck(workspace.id, worktree.path)
        case .behind:
            return .updatePullRequestBranch(workspace.id, worktree.path)
        case .review:
            return .openPullRequest(workspace.id, worktree.path)
        case .ready:
            return .queuePullRequest(workspace.id, worktree.path)
        }
    }

    private var reviewStatus: String? {
        if !pullRequest.changesRequestedByLogins.isEmpty {
            return overviewLocalizedFormat("overview.model.changesRequestedByFormat", pullRequest.changesRequestedByLogins.joined(separator: ", "))
        }
        if !pullRequest.requestedReviewerLogins.isEmpty {
            return overviewLocalizedFormat("overview.model.waitingOnFormat", pullRequest.requestedReviewerLogins.joined(separator: ", "))
        }
        if !pullRequest.approvedByLogins.isEmpty {
            return overviewLocalizedFormat("overview.model.approvedByFormat", pullRequest.approvedByLogins.joined(separator: ", "))
        }
        return nil
    }

    private var checkStatus: String? {
        guard let checksSummary else {
            return latestRun?.title.nilIfEmpty
        }
        if checksSummary.failingCount > 0 {
            return checksSummary.failingChecks.first?.name ?? overviewLocalizedFormat("overview.model.failingChecksCountFormat", checksSummary.failingCount)
        }
        if checksSummary.pendingCount > 0 {
            return overviewLocalizedFormat("overview.model.pendingChecksFormat", checksSummary.pendingCount)
        }
        if checksSummary.passingCount > 0 {
            return overviewLocalizedFormat("overview.model.passingChecksFormat", checksSummary.passingCount)
        }
        return nil
    }

    private func detailParts(_ values: [String?], fallback: String?) -> String {
        let joined = values.compactMap { $0?.nilIfEmpty }.joined(separator: " · ")
        return joined.nilIfEmpty ?? fallback ?? ""
    }
}

struct OverviewFailingWorkspace: Identifiable {
    let workspace: OverviewWorkspaceSnapshot
    let worktree: WorktreeModel
    let failingCount: Int
    let firstFailingCheckName: String?

    var id: String {
        "\(workspace.id.uuidString):\(worktree.path)"
    }
}

struct OverviewReadyWorkspace: Identifiable {
    let workspace: OverviewWorkspaceSnapshot
    let worktree: WorktreeModel
    let number: Int
    let title: String
    let detail: String

    var id: String {
        "\(workspace.id.uuidString):ready:\(worktree.path)"
    }
}

struct OverviewBlockedWorkspace: Identifiable {
    let workspace: OverviewWorkspaceSnapshot
    let worktree: WorktreeModel
    let number: Int
    let title: String
    let readiness: GitHubMergeReadiness
    let requestedReviewerLogins: [String]
    let changesRequestedByLogins: [String]
    let checksSummary: GitHubPullRequestChecksSummary?

    var id: String {
        "\(workspace.id.uuidString):blocked:\(worktree.path):\(readiness.rawValue)"
    }

    var readinessDetail: String {
        switch readiness {
        case .behind:
            return overviewLocalized("overview.blocked.behindDetail")
        case .changesRequested:
            if !changesRequestedByLogins.isEmpty {
                return overviewLocalizedFormat("overview.model.changesRequestedByFormat", changesRequestedByLogins.joined(separator: ", ")) + "."
            }
            return overviewLocalized("overview.blocked.reviewRequestedFallback")
        case .conflicted:
            return overviewLocalized("overview.blocked.resolveConflicts")
        case .blocked:
            return overviewLocalized("overview.blocked.mergeBlocked")
        case .draft:
            return overviewLocalized("overview.blocked.stillDraft")
        case .checking:
            if !requestedReviewerLogins.isEmpty {
                return overviewLocalizedFormat("overview.model.waitingOnFormat", requestedReviewerLogins.joined(separator: ", ")) + "."
            }
            if let checksSummary, checksSummary.pendingCount > 0 {
                return overviewLocalizedFormat("overview.blocked.pendingChecksFormat", checksSummary.pendingCount)
            }
            return title
        case .ready, .closed:
            return title
        }
    }

    var focusHeadline: String {
        switch readiness {
        case .behind:
            return overviewLocalized("overview.blocked.focus.updateBranch")
        case .changesRequested:
            return overviewLocalized("overview.blocked.focus.addressReviewFeedback")
        case .conflicted:
            return overviewLocalized("overview.blocked.focus.resolveConflicts")
        case .blocked:
            return overviewLocalized("overview.blocked.focus.clearBlockers")
        case .draft:
            return overviewLocalized("overview.blocked.focus.decideDraft")
        case .checking:
            return overviewLocalized("overview.blocked.focus.pushReview")
        case .ready, .closed:
            return title
        }
    }

    var primaryActionLabel: String {
        readiness == .behind ? overviewLocalized("overview.blocked.action.updateBranch") : overviewLocalized("overview.blocked.action.openPR")
    }

    var primaryAction: OverviewWorkspaceAction {
        readiness == .behind
            ? .updatePullRequestBranch(workspace.id, worktree.path)
            : .openPullRequest(workspace.id, worktree.path)
    }
}

extension GitHubMergeReadiness {
    var blockerTitle: String {
        switch self {
        case .behind:
            return overviewLocalized("overview.blockerTitle.behind")
        case .changesRequested:
            return overviewLocalized("overview.blockerTitle.changesRequested")
        case .conflicted:
            return overviewLocalized("overview.blockerTitle.conflicted")
        case .blocked:
            return overviewLocalized("overview.blockerTitle.blocked")
        case .draft:
            return overviewLocalized("overview.blockerTitle.draft")
        case .checking:
            return overviewLocalized("overview.blockerTitle.checking")
        case .ready, .closed:
            return label
        }
    }
}
