//
//  WorkspaceCommands.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

struct WorkspaceGitHubTarget: Hashable {
    let workspaceID: UUID
    let worktreePath: String
}

enum WorkspaceCommand: Hashable {
    case toggleCommandPalette
    case toggleOverview
    case presentSettings
    case dismissTransientUI
    case checkForUpdates
    case openLatestRelease
    case selectWorkspace(UUID)
    case refreshWorkspace(UUID)
    case refreshAllRepositories
    case createSession(UUID)
    case splitFocusedPane(UUID, PaneSplitAxis)
    case createWorktree(UUID)
    case createSSHSession(UUID)
    case createAgentSession(UUID, AgentPreset?)
    case launchHAPISession(UUID)
    case startHAPIHub(UUID)
    case openRemoteTargetShell(UUID, UUID)
    case openRemoteTargetAgent(UUID, UUID)
    case runWorkspaceScript(UUID)
    case runSetupScript(UUID)
    case runWorkflow(UUID, UUID)
    case toggleWorkspacePinned(UUID)
    case toggleWorkspaceArchived(UUID)
    case toggleShowArchived
    case openPullRequest(UUID, String)
    case markPullRequestReady(UUID, String)
    case updatePullRequestBranch(UUID, String)
    case queuePullRequest(UUID, String)
    case copyPullRequestReleaseNotes(UUID, String)
    case updatePullRequestBranches([WorkspaceGitHubTarget])
    case queuePullRequests([WorkspaceGitHubTarget])
    case copyPullRequestReleaseNotesBatch([WorkspaceGitHubTarget])
    case openLatestRun(UUID, String)
    case openFailingCheckDetails(UUID, String)
    case copyFailingCheckURL(UUID, String)
    case rerunLatestFailedJobs(UUID, String)
    case copyLatestRunLogs(UUID, String)
}

enum WorkspaceEvent {
    case autoRefreshTick
    case workspaceWatchTriggered(UUID)
    case gitHubIntegrationStateUpdated(GitHubIntegrationState)
    case statusMessage(String, WorkspaceStatusTone, deliverSystemNotification: Bool)
}

enum CommandPaletteGroup: String, CaseIterable, Hashable, Identifiable {
    case recent
    case navigation
    case sessions
    case automation
    case releases
    case workflows
    case github

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent:
            return "Recent"
        case .navigation:
            return "Navigation"
        case .sessions:
            return "Sessions"
        case .automation:
            return "Automation"
        case .releases:
            return "Releases"
        case .workflows:
            return "Workflows"
        case .github:
            return "GitHub"
        }
    }
}

struct CommandPaletteItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case command(WorkspaceCommand)
    }

    let id: String
    let title: String
    let subtitle: String?
    let group: CommandPaletteGroup
    let keywords: [String]
    let isGlobal: Bool
    let kind: Kind

    var searchableText: String {
        ([title, subtitle] + keywords)
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
    }

    func score(query: String, recency: TimeInterval?) -> Double? {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let recencyScore = recency.map { min(max($0, 0), 4_000_000_000) / 4_000_000_000 } ?? 0
        guard !normalized.isEmpty else {
            return Double(isGlobal ? 100 : 60) + recencyScore
        }

        let haystack = searchableText
        guard let range = haystack.range(of: normalized) else {
            let tokenScore = normalized
                .split(whereSeparator: \.isWhitespace)
                .reduce(0.0) { partial, token in
                    haystack.contains(String(token)) ? partial + 12 : partial
                }
            if tokenScore == 0 {
                return nil
            }
            return tokenScore + recencyScore
        }

        let prefixBoost = haystack.hasPrefix(normalized) ? 40.0 : 0.0
        let titleBoost = title.lowercased().contains(normalized) ? 18.0 : 0.0
        let distancePenalty = Double(haystack.distance(from: haystack.startIndex, to: range.lowerBound)) * 0.15
        return 100 + prefixBoost + titleBoost + recencyScore - distancePenalty
    }
}

struct CommandPaletteSection: Identifiable, Hashable {
    let group: CommandPaletteGroup
    let items: [CommandPaletteItem]

    var id: String { group.id }
}

enum GitHubBatchCommandPaletteFactory {
    static func makeItems(
        readyTargets: [WorkspaceGitHubTarget],
        behindTargets: [WorkspaceGitHubTarget],
        releasableTargets: [WorkspaceGitHubTarget]
    ) -> [CommandPaletteItem] {
        var items: [CommandPaletteItem] = []

        if !readyTargets.isEmpty {
            items.append(
                CommandPaletteItem(
                    id: "github-batch-queue-ready",
                    title: "Queue \(readyTargets.count) Merge-Ready PRs",
                    subtitle: "Cross-repo auto-merge batch",
                    group: .github,
                    keywords: ["github", "batch", "merge queue", "ship"],
                    isGlobal: true,
                    kind: .command(.queuePullRequests(readyTargets))
                )
            )
        }

        if !behindTargets.isEmpty {
            items.append(
                CommandPaletteItem(
                    id: "github-batch-update-behind",
                    title: "Update \(behindTargets.count) Behind PRs",
                    subtitle: "Cross-repo rebase batch",
                    group: .github,
                    keywords: ["github", "batch", "update branch", "rebase"],
                    isGlobal: true,
                    kind: .command(.updatePullRequestBranches(behindTargets))
                )
            )
        }

        if !releasableTargets.isEmpty {
            items.append(
                CommandPaletteItem(
                    id: "github-batch-release-notes",
                    title: "Copy Ship Notes for \(releasableTargets.count) PRs",
                    subtitle: "Combined release draft bundle",
                    group: .github,
                    keywords: ["github", "batch", "release notes", "changelog"],
                    isGlobal: true,
                    kind: .command(.copyPullRequestReleaseNotesBatch(releasableTargets))
                )
            )
        }

        return items
    }
}
