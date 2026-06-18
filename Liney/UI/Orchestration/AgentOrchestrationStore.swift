//
//  AgentOrchestrationStore.swift
//  Liney
//
//  Author: everettjf
//

import Combine
import Foundation

/// Aggregates the agent state across every open workspace into the rows the
/// orchestration panel renders. Pulls from the same signals as `liney agents`
/// — passive process detection (`AgentProcessDetector`) merged with the
/// `liney status` self-reports (`AgentStatusStore`) — and enriches each row
/// with branch / PR / listening-port context for navigation.
@MainActor
final class AgentOrchestrationStore: ObservableObject {
    @Published private(set) var groups: [AgentOrchestrationGroup] = []
    @Published private(set) var summary: String = "No agents running"
    @Published private(set) var notifications: [IslandNotificationItem] = []
    @Published private(set) var hasAnyAgents: Bool = false

    /// Supplies the live set of workspace stores to scan. Injected so the
    /// window manager can hand in `LineyDesktopApplication.allWorkspaceStores`
    /// and tests can drive the pure model directly.
    private let storesProvider: () -> [WorkspaceStore]
    private let detector: (pid_t) -> AgentProcessDetector.Detected?

    init(
        storesProvider: @escaping () -> [WorkspaceStore],
        detector: @escaping (pid_t) -> AgentProcessDetector.Detected? = { AgentProcessDetector.detect(rootPID: $0) }
    ) {
        self.storesProvider = storesProvider
        self.detector = detector
    }

    func refresh() {
        var rows: [AgentOrchestrationRow] = []
        for store in storesProvider() {
            for workspace in store.workspaces where workspace.isActive {
                let focusedPane = workspace.sessionController.focusedPaneID
                let pr = workspace.supportsRepositoryFeatures
                    ? workspace.gitHubStatus(for: workspace.activeWorktreePath)?.pullRequest
                    : nil
                for (paneID, session) in workspace.sessionController.sessions {
                    let entry = AgentStatusStore.shared.entries[paneID]
                    var type: String?
                    var name: String? = entry?.agentName
                    var detected = false
                    if let pid = session.pid, let hit = detector(pid) {
                        type = hit.type
                        if name == nil { name = hit.displayName }
                        detected = true
                    }
                    guard entry != nil || detected else { continue }
                    rows.append(
                        AgentOrchestrationRow(
                            workspaceID: workspace.id,
                            workspaceName: workspace.name,
                            worktreePath: workspace.activeWorktreePath,
                            branch: workspace.supportsRepositoryFeatures ? workspace.currentBranch : nil,
                            prNumber: pr?.number,
                            prState: pr.map { $0.isDraft ? "DRAFT" : $0.state.uppercased() },
                            paneID: paneID,
                            agentType: type,
                            agentName: name,
                            status: entry?.state ?? .running,
                            reported: entry != nil,
                            cwd: session.effectiveWorkingDirectory,
                            focused: paneID == focusedPane,
                            listeningPorts: workspace.listeningPorts,
                            changedFileCount: workspace.supportsRepositoryFeatures ? workspace.changedFileCount : 0
                        )
                    )
                }
            }
        }

        groups = AgentOrchestrationOrdering.grouped(rows)
        summary = AgentOrchestrationOrdering.summary(rows)
        hasAnyAgents = !rows.isEmpty
        notifications = Array(IslandNotificationState.shared.items.suffix(8).reversed())
    }
}
