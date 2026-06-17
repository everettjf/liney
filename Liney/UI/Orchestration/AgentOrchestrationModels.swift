//
//  AgentOrchestrationModels.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

/// One agent pane in the cross-worktree orchestration panel: a single cell of
/// the worktree × agent matrix.
struct AgentOrchestrationRow: Identifiable, Equatable {
    let workspaceID: UUID
    let workspaceName: String
    let worktreePath: String
    let branch: String?
    let prNumber: Int?
    let prState: String?
    let paneID: UUID
    let agentType: String?
    let agentName: String?
    let status: AgentReportedState
    /// True when `status` came from a `liney status` self-report; false when it
    /// was inferred from passive process detection.
    let reported: Bool
    let cwd: String
    let focused: Bool
    let listeningPorts: [Int]

    var id: UUID { paneID }

    /// Best label for the agent, falling back through name → type → "agent".
    var displayName: String {
        agentName ?? agentType ?? "agent"
    }
}

/// Agent rows grouped under one workspace, for the panel's sectioned list.
struct AgentOrchestrationGroup: Identifiable, Equatable {
    let workspaceID: UUID
    let workspaceName: String
    var rows: [AgentOrchestrationRow]

    var id: UUID { workspaceID }
}

enum AgentOrchestrationOrdering {
    /// Attention-first ordering: a blocked agent should float to the top so the
    /// user lands on "who needs me" without scanning. Lower sorts earlier.
    static func priority(_ status: AgentReportedState) -> Int {
        switch status {
        case .waiting: return 0
        case .error: return 1
        case .running: return 2
        case .done: return 3
        }
    }

    /// Stable, attention-first order across a flat row list: by status
    /// priority, then workspace name, then pane id (deterministic tiebreak).
    static func sorted(_ rows: [AgentOrchestrationRow]) -> [AgentOrchestrationRow] {
        rows.sorted { lhs, rhs in
            let lp = priority(lhs.status), rp = priority(rhs.status)
            if lp != rp { return lp < rp }
            if lhs.workspaceName != rhs.workspaceName {
                return lhs.workspaceName.localizedCaseInsensitiveCompare(rhs.workspaceName) == .orderedAscending
            }
            return lhs.paneID.uuidString < rhs.paneID.uuidString
        }
    }

    /// Groups rows by workspace, ordering the groups by their most urgent row
    /// (so the workspace with a blocked agent comes first) and ordering rows
    /// within a group attention-first.
    static func grouped(_ rows: [AgentOrchestrationRow]) -> [AgentOrchestrationGroup] {
        var byWorkspace: [UUID: AgentOrchestrationGroup] = [:]
        var order: [UUID] = []
        for row in sorted(rows) {
            if byWorkspace[row.workspaceID] == nil {
                byWorkspace[row.workspaceID] = AgentOrchestrationGroup(
                    workspaceID: row.workspaceID,
                    workspaceName: row.workspaceName,
                    rows: []
                )
                order.append(row.workspaceID)
            }
            byWorkspace[row.workspaceID]?.rows.append(row)
        }
        // `order` already follows the sorted-rows order, so the first workspace
        // seen owns the most urgent row.
        return order.compactMap { byWorkspace[$0] }
    }

    /// Headline counts for the panel header, e.g. "2 waiting · 3 running".
    static func summary(_ rows: [AgentOrchestrationRow]) -> String {
        guard !rows.isEmpty else { return "No agents running" }
        var counts: [AgentReportedState: Int] = [:]
        for row in rows { counts[row.status, default: 0] += 1 }
        let parts: [String] = [
            (.waiting, "waiting"), (.running, "running"), (.error, "error"), (.done, "done"),
        ].compactMap { state, label in
            guard let n = counts[state], n > 0 else { return nil }
            return "\(n) \(label)"
        }
        return parts.joined(separator: " · ")
    }
}
