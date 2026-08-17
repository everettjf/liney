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
nonisolated final class AgentStatusStore: @unchecked Sendable {
    static let shared = AgentStatusStore()

    struct Entry: Equatable {
        var state: AgentReportedState
        var title: String?
        var agentName: String?
        var updatedAt: Date
    }

    private var storedEntries: [UUID: Entry] = [:]
    private let lock = NSLock()

    var entries: [UUID: Entry] {
        withLock { storedEntries }
    }

    private let now: () -> Date

    /// `now` is injectable so tests can assert timestamps deterministically.
    init(now: @escaping () -> Date = { Date() }) {
        self.now = now
    }

    func update(pane: UUID, state: AgentReportedState, title: String?, agentName: String? = nil) {
        let entry = Entry(state: state, title: title, agentName: agentName, updatedAt: now())
        withLock {
            storedEntries[pane] = entry
        }
    }

    func state(for pane: UUID) -> AgentReportedState? {
        withLock { storedEntries[pane]?.state }
    }

    func clear(pane: UUID) {
        withLock {
            storedEntries[pane] = nil
        }
    }

    func clearAll() {
        withLock {
            storedEntries.removeAll()
        }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
