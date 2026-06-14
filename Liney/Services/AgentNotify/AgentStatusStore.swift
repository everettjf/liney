//
//  AgentStatusStore.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

/// In-memory record of the last state each pane's agent reported via
/// `liney status`. Read by `session-list` so orchestration tooling can see
/// which agent is blocked, finished, or errored without scraping scrollback.
///
/// Keyed by pane UUID. Entries for closed panes are never read (session-list
/// only iterates live panes) so no active eviction is required; `clear(pane:)`
/// is provided for callers that want to prune on pane close.
@MainActor
final class AgentStatusStore {
    static let shared = AgentStatusStore()

    struct Entry: Equatable {
        var state: AgentReportedState
        var title: String?
        var updatedAt: Date
    }

    private(set) var entries: [UUID: Entry] = [:]

    private let now: () -> Date

    /// `now` is injectable so tests can assert timestamps deterministically.
    init(now: @escaping () -> Date = { Date() }) {
        self.now = now
    }

    func update(pane: UUID, state: AgentReportedState, title: String?) {
        entries[pane] = Entry(state: state, title: title, updatedAt: now())
    }

    func state(for pane: UUID) -> AgentReportedState? {
        entries[pane]?.state
    }

    func clear(pane: UUID) {
        entries[pane] = nil
    }

    func clearAll() {
        entries.removeAll()
    }
}
