import Foundation
import CoreGraphics

enum WorkbenchViewport {
    static func shouldMount(center: CGPoint, size: CGSize, scale: CGFloat, viewport: CGSize, isSelected: Bool) -> Bool {
        // Keep the focused card mounted and prefetch nearby cards to avoid churn at edges.
        guard !isSelected, viewport.width > 0, viewport.height > 0 else { return true }
        let bounds = CGRect(x: center.x - size.width * scale / 2,
                            y: center.y - size.height * scale / 2,
                            width: size.width * scale, height: size.height * scale)
        return CGRect(origin: .zero, size: viewport).insetBy(dx: -160, dy: -160).intersects(bounds)
    }
}

@MainActor
struct WorkbenchAttention: Identifiable {
    enum Action { case terminal, checks, pullRequest, refresh }
    let item: WorkbenchItem
    let priority: Int
    let headline: String
    let details: String
    let updatedAt: Date?
    let action: Action
    var id: String { "\(item.id.workspaceID)::\(item.id.worktreePath)" }
    var isUnread: Bool { item.isUnread }
    var actionLabel: String {
        switch action {
        case .terminal: return "workbench.resume"
        case .checks: return "workbench.checks"
        case .pullRequest: return "workbench.pullRequest"
        case .refresh: return "workbench.refresh"
        }
    }

    static func make(items: [WorkbenchItem]) -> [WorkbenchAttention] {
        let localized = LocalizationManager.shared.string
        let groups = Dictionary(grouping: items) { "\($0.id.workspaceID)::\($0.id.worktreePath)" }
        return groups.values.compactMap { group in
            let ordered = group.sorted {
                let left = $0.agent?.state == .waiting ? 0 : ($0.agent?.state == .error ? 1 : 2)
                let right = $1.agent?.state == .waiting ? 0 : ($1.agent?.state == .error ? 1 : 2)
                if left != right { return left < right }
                if $0.isUnread != $1.isUnread { return $0.isUnread }
                return $0.id.id < $1.id.id
            }
            guard let item = ordered.first else { return nil }
            let status = item.workspace.gitHubStatuses[item.id.worktreePath]
            var details: [String] = []
            let attentionCount = group.filter(\.needsAttention).count
            if attentionCount > 1 {
                details.append(l10nFormat(localized("workbench.attentionTabs"), arguments: [attentionCount]))
            }
            if item.changedFileCount > 0 { details.append("\(item.changedFileCount) " + localized("workbench.changed")) }
            if let failure = status?.refreshError { details.append(localized("workbench.stale") + ": " + failure) }
            if let count = status?.checksSummary?.failingCount, count > 0 {
                details.append("\(count) " + localized("workbench.failingChecks"))
            }
            if item.needsAttention {
                let waiting = item.agent?.state == .waiting
                return WorkbenchAttention(item: item, priority: waiting ? 0 : 1,
                    headline: item.agent?.title ?? localized(item.statusKey),
                    details: ([item.tab.title] + details).joined(separator: " · "),
                    updatedAt: item.agent?.updatedAt, action: .terminal)
            }
            if status?.refreshError != nil {
                return WorkbenchAttention(item: item, priority: 4, headline: localized("workbench.stale"),
                    details: details.joined(separator: " · "), updatedAt: status?.refreshedAt, action: .refresh)
            }
            if let checks = status?.checksSummary, checks.failingCount > 0 {
                return WorkbenchAttention(item: item, priority: 2, headline: localized("workbench.failingChecks"),
                    details: ([checks.failingChecks.first?.name ?? ""] + details).joined(separator: " · "),
                    updatedAt: status?.refreshedAt, action: .checks)
            }
            if let pr = status?.pullRequest, pr.isOpen, pr.mergeReadiness == .ready, !pr.needsReviewerAttention {
                return WorkbenchAttention(item: item, priority: 3, headline: localized("workbench.readyPR"),
                    details: "#\(pr.number) · \(pr.title)", updatedAt: status?.refreshedAt, action: .pullRequest)
            }
            return nil
        }.sorted { $0.priority == $1.priority ? $0.id < $1.id : $0.priority < $1.priority }
    }
}

/// A tab's identity is shared by Overview, Canvas and persisted pin layouts.
struct WorkbenchLocation: Hashable {
    var cardID: GlobalCanvasCardID
    var paneID: UUID?
}

@MainActor
struct WorkbenchItem: Identifiable {
    let workspace: WorkspaceModel
    let tab: WorkspaceTabStateRecord
    let location: WorkbenchLocation
    let controller: WorkspaceSessionController?
    let agent: AgentStatusStore.Entry?
    let isPinned: Bool
    let lastVisitedAt: Date?

    var id: GlobalCanvasCardID { location.cardID }
    var needsAttention: Bool { agent?.state == .waiting || agent?.state == .error }
    var isUnread: Bool {
        guard needsAttention, let agent else { return false }
        return lastVisitedAt.map { $0 < agent.updatedAt } ?? true
    }
    var isStarted: Bool {
        controller?.sessions.values.contains { $0.lifecycle != .idle } ?? false
    }
    var directory: String {
        if let paneID = location.paneID, let session = controller?.session(for: paneID) {
            return session.effectiveWorkingDirectory
        }
        return id.worktreePath
    }
    var context: String {
        let branch = workspace.worktrees.first { $0.path == id.worktreePath }?.branch
        return workspace.supportsRepositoryFeatures ? (branch ?? id.worktreePath.abbreviatedPath) : directory.abbreviatedPath
    }
    var changedFileCount: Int {
        guard workspace.supportsRepositoryFeatures else { return 0 }
        return workspace.worktreeStatuses[id.worktreePath]?.changedFileCount
            ?? (workspace.activeWorktreePath == id.worktreePath ? workspace.changedFileCount : 0)
    }
    var statusKey: String {
        switch agent?.state {
        case .waiting: return "workbench.waiting"
        case .error: return "workbench.error"
        case .running: return "workbench.working"
        case .done: return "workbench.done"
        case nil: return isStarted ? "workbench.session" : "workbench.saved"
        }
    }
}

extension WorkspaceStore {
    /// Enumeration reads only existing controllers. It must never wake a saved tab.
    func workbenchItems() -> [WorkbenchItem] {
        let agents = AgentStatusStore.shared.entries
        let pins = Set(globalCanvasState.cardLayouts.filter(\.isPinned).map(\.cardID))
        return workspaces.filter { !$0.isArchived }.flatMap { workspace in
            workspace.canvasStates().flatMap { state in
                state.tabs.map { tab in
                    let id = GlobalCanvasCardID(workspaceID: workspace.id, worktreePath: state.worktreePath, tabID: tab.id)
                    let controller = workspace.existingTabController(for: state.worktreePath, tabID: tab.id)
                    let reported = tab.panes.compactMap { pane -> (UUID, AgentStatusStore.Entry)? in
                        guard let entry = agents[pane.id] else { return nil }
                        return (pane.id, entry)
                    }.sorted {
                        let lhsPriority = Self.agentAttentionPriority($0.1)
                        let rhsPriority = Self.agentAttentionPriority($1.1)
                        return lhsPriority == rhsPriority ? $0.1.updatedAt > $1.1.updatedAt : lhsPriority < rhsPriority
                    }.first
                    return WorkbenchItem(workspace: workspace, tab: tab,
                        location: WorkbenchLocation(cardID: id, paneID: reported?.0 ?? controller?.focusedPaneID ?? tab.focusedPaneID),
                        controller: controller, agent: reported?.1, isPinned: pins.contains(id),
                        lastVisitedAt: workspace.settings.workbenchVisits[id.id])
                }
            }
        }
    }

    private static func agentAttentionPriority(_ entry: AgentStatusStore.Entry) -> Int {
        switch entry.state {
        case .waiting: return 0
        case .error: return 1
        case .running: return 2
        case .done: return 3
        }
    }

    func recordWorkbenchVisit(_ workspace: WorkspaceModel, at date: Date = Date()) {
        guard let tabID = workspace.activeTabID else { return }
        let id = GlobalCanvasCardID(workspaceID: workspace.id, worktreePath: workspace.activeWorktreePath, tabID: tabID)
        workspace.settings.workbenchVisits[id.id] = date
    }

    func openWorkbenchLocation(_ location: WorkbenchLocation, inCanvas: Bool = false) {
        guard workspaces.contains(where: { $0.id == location.cardID.workspaceID && $0.canvasCardIDs().contains(location.cardID) }) else { return }
        selectGlobalCanvasCard(location.cardID)
        isOverviewPresented = false
        isCanvasPresented = inCanvas
        if let paneID = location.paneID, let workspace = selectedWorkspace,
           workspace.id == location.cardID.workspaceID {
            workspace.focusPane(paneID)
            DispatchQueue.main.async { workspace.sessionController.focus(paneID) }
        }
    }

    func toggleWorkbenchPin(_ id: GlobalCanvasCardID) {
        var state = globalCanvasState
        if let index = state.cardLayouts.firstIndex(where: { $0.cardID == id }) {
            state.cardLayouts[index].isPinned.toggle()
        } else {
            state.cardLayouts.append(GlobalCanvasCardLayoutRecord(
                workspaceID: id.workspaceID, worktreePath: id.worktreePath, tabID: id.tabID,
                centerX: 312, centerY: 308, width: 560, height: 360, isPinned: true))
        }
        updateGlobalCanvasState(state)
    }
}
