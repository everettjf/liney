//
//  IslandNotificationState.swift
//  Liney
//
//  Author: everettjf
//

import Combine
import Foundation

enum IslandTab: String, CaseIterable {
    case workspaces
    case notifications
}

@MainActor
final class IslandNotificationState: ObservableObject {
    static let shared = IslandNotificationState()

    @Published var items: [IslandNotificationItem] = []
    @Published var isExpanded: Bool = false
    @Published var selectedTab: IslandTab = .workspaces

    var latestItem: IslandNotificationItem? {
        items.last
    }

    var badgeCount: Int {
        items.count
    }

    func post(item: IslandNotificationItem) {
        if let index = items.firstIndex(where: { $0.workspaceID == item.workspaceID && $0.worktreePath == item.worktreePath }) {
            items[index] = item
        } else {
            items.append(item)
        }
    }

    func markDone(id: UUID) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].status = .done
        }
    }

    func dismiss(id: UUID) {
        items.removeAll { $0.id == id }
        if items.isEmpty {
            isExpanded = false
        }
    }

    func clearAll() {
        items.removeAll()
        isExpanded = false
    }
}
