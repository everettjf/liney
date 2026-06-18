//
//  AgentOrchestrationTests.swift
//  LineyTests
//
//  Author: everettjf
//

import XCTest
@testable import Liney

final class AgentOrchestrationOrderingTests: XCTestCase {
    private func row(
        workspace: String,
        ws: UUID = UUID(),
        pane: UUID = UUID(),
        status: AgentReportedState,
        reported: Bool = true,
        changedFileCount: Int = 0
    ) -> AgentOrchestrationRow {
        AgentOrchestrationRow(
            workspaceID: ws,
            workspaceName: workspace,
            worktreePath: "/repo/\(workspace)",
            branch: "main",
            prNumber: nil,
            prState: nil,
            paneID: pane,
            agentType: "claude-code",
            agentName: "Claude Code",
            status: status,
            reported: reported,
            cwd: "/repo/\(workspace)",
            focused: false,
            listeningPorts: [],
            changedFileCount: changedFileCount
        )
    }

    func testCanReviewDiffReflectsChangedFiles() {
        XCTAssertFalse(row(workspace: "a", status: .running, changedFileCount: 0).canReviewDiff)
        XCTAssertTrue(row(workspace: "a", status: .running, changedFileCount: 3).canReviewDiff)
    }

    func testStatusPriorityIsAttentionFirst() {
        XCTAssertLessThan(AgentOrchestrationOrdering.priority(.waiting), AgentOrchestrationOrdering.priority(.error))
        XCTAssertLessThan(AgentOrchestrationOrdering.priority(.error), AgentOrchestrationOrdering.priority(.running))
        XCTAssertLessThan(AgentOrchestrationOrdering.priority(.running), AgentOrchestrationOrdering.priority(.done))
    }

    func testSortedFloatsWaitingToTop() {
        let rows = [
            row(workspace: "a", status: .done),
            row(workspace: "b", status: .running),
            row(workspace: "c", status: .waiting),
            row(workspace: "d", status: .error),
        ]
        let sorted = AgentOrchestrationOrdering.sorted(rows)
        XCTAssertEqual(sorted.map(\.status), [.waiting, .error, .running, .done])
    }

    func testSortedTiebreaksByWorkspaceName() {
        let rows = [
            row(workspace: "zeta", status: .running),
            row(workspace: "alpha", status: .running),
        ]
        let sorted = AgentOrchestrationOrdering.sorted(rows)
        XCTAssertEqual(sorted.map(\.workspaceName), ["alpha", "zeta"])
    }

    func testGroupedPutsMostUrgentWorkspaceFirst() {
        let calm = UUID(), urgent = UUID()
        let rows = [
            row(workspace: "calm", ws: calm, status: .running),
            row(workspace: "calm", ws: calm, status: .done),
            row(workspace: "urgent", ws: urgent, status: .waiting),
        ]
        let groups = AgentOrchestrationOrdering.grouped(rows)
        XCTAssertEqual(groups.first?.workspaceName, "urgent", "workspace with a waiting agent leads")
        XCTAssertEqual(groups.count, 2)
        // Within the calm group, running sorts before done.
        XCTAssertEqual(groups.last?.rows.map(\.status), [.running, .done])
    }

    func testSummaryCountsByState() {
        let ws = UUID()
        let rows = [
            row(workspace: "a", ws: ws, status: .waiting),
            row(workspace: "a", ws: ws, status: .waiting),
            row(workspace: "a", ws: ws, status: .running),
        ]
        XCTAssertEqual(AgentOrchestrationOrdering.summary(rows), "2 waiting · 1 running")
    }

    func testSummaryEmpty() {
        XCTAssertEqual(AgentOrchestrationOrdering.summary([]), "No agents running")
    }
}
