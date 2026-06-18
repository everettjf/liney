//
//  IslandNotificationModels.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

enum IslandItemStatus {
    case running
    case done
    case error
    case waitingForInput
}

struct IslandNotificationItem: Identifiable {
    let id: UUID
    let workspaceID: UUID
    let worktreePath: String?
    let title: String
    let agentName: String?
    let terminalTag: String?
    var status: IslandItemStatus
    let startedAt: Date
    var body: String?
    var prompt: IslandPrompt?
    /// Uncommitted changed-file count in the item's worktree, attached when an
    /// agent reports `done` so the island can offer a one-click diff review.
    var changedFileCount: Int? = nil
}

struct IslandPrompt {
    let question: String
    let options: [IslandPromptOption]
}

struct IslandPromptOption: Identifiable {
    let id: Int
    let label: String
    let responseText: String
}
