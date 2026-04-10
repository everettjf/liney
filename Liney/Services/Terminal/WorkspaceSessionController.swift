//
//  WorkspaceSessionController.swift
//  Liney
//
//  Author: everettjf
//

import Combine
import Foundation

@MainActor
final class WorkspaceSessionController: ObservableObject {
    let workspaceID: UUID

    @Published private(set) var sessions: [UUID: ShellSession] = [:]
    @Published var focusedPaneID: UUID? {
        didSet {
            updateSessionFocusStates()
        }
    }
    @Published var previousFocusedPaneID: UUID?

    init(workspaceID: UUID, paneSnapshots: [PaneSnapshot]) {
        self.workspaceID = workspaceID
        replaceSessions(with: paneSnapshots, focusedPaneID: paneSnapshots.first?.id, defaultWorkingDirectory: paneSnapshots.first?.preferredWorkingDirectory ?? NSHomeDirectory())
    }

    var activeSessionCount: Int {
        sessions.values.filter(\.hasActiveProcess).count
    }

    var quitConfirmationSessionCount: Int {
        sessions.values.filter(\.needsQuitConfirmation).count
    }

    var runningSessionCount: Int {
        sessions.values.filter(\.isRunning).count
    }

    func session(for paneID: UUID) -> ShellSession? {
        sessions[paneID]
    }

    func replaceSessions(with paneSnapshots: [PaneSnapshot], focusedPaneID: UUID?, defaultWorkingDirectory: String) {
        sessions.values.forEach { $0.terminate() }
        sessions.removeAll()

        let preparedSnapshots = paneSnapshots.isEmpty ? [PaneSnapshot.makeDefault(cwd: defaultWorkingDirectory)] : paneSnapshots
        for snapshot in preparedSnapshots {
            sessions[snapshot.id] = ShellSession(snapshot: snapshot)
        }
        self.focusedPaneID = focusedPaneID ?? preparedSnapshots.first?.id
        self.previousFocusedPaneID = nil
        sync(with: preparedSnapshots.map(\.id), defaultWorkingDirectory: defaultWorkingDirectory)
    }

    func sync(with paneIDs: [UUID], defaultWorkingDirectory: String) {
        let wanted = Set(paneIDs)
        let existing = Set(sessions.keys)

        for missing in wanted.subtracting(existing) {
            let snapshot = PaneSnapshot.makeDefault(id: missing, cwd: defaultWorkingDirectory)
            sessions[missing] = ShellSession(snapshot: snapshot)
        }

        for removed in existing.subtracting(wanted) {
            sessions[removed]?.terminate()
            sessions.removeValue(forKey: removed)
        }

        for paneID in paneIDs {
            sessions[paneID]?.startIfNeeded()
        }

        if focusedPaneID == nil || focusedPaneID.map({ wanted.contains($0) }) == false {
            focusedPaneID = paneIDs.first
        }
        updateSessionFocusStates()
    }

    func createPane(defaultWorkingDirectory: String) -> UUID {
        let snapshot = PaneSnapshot.makeDefault(cwd: defaultWorkingDirectory)
        return createPane(from: snapshot)
    }

    func createPane(from snapshot: PaneSnapshot) -> UUID {
        let session = ShellSession(snapshot: snapshot)
        sessions[snapshot.id] = session
        focusedPaneID = snapshot.id
        session.startIfNeeded()
        return snapshot.id
    }

    func closePane(_ paneID: UUID) {
        sessions[paneID]?.terminate()
        sessions.removeValue(forKey: paneID)
        if focusedPaneID == paneID {
            focusedPaneID = sessions.keys.sorted { $0.uuidString < $1.uuidString }.first
        }
    }

    func focus(_ paneID: UUID) {
        guard let session = sessions[paneID] else { return }
        if focusedPaneID != paneID {
            previousFocusedPaneID = focusedPaneID
        }
        focusedPaneID = paneID
        session.focus()
    }

    func focusNext(using order: [UUID]) {
        guard let focusedPaneID, !order.isEmpty else {
            if let first = order.first {
                focus(first)
            }
            return
        }
        guard let index = order.firstIndex(of: focusedPaneID) else {
            focus(order[0])
            return
        }
        focus(order[(index + 1) % order.count])
    }

    func focusPrevious(using order: [UUID]) {
        guard let focusedPaneID, !order.isEmpty else {
            if let first = order.first {
                focus(first)
            }
            return
        }
        guard let index = order.firstIndex(of: focusedPaneID) else {
            focus(order[0])
            return
        }
        focus(order[(index - 1 + order.count) % order.count])
    }

    func restartFocused() {
        guard let focusedPaneID, let session = sessions[focusedPaneID] else { return }
        session.restart()
    }

    func restartAll() {
        for session in sessions.values {
            session.restart()
        }
    }

    func clearFocused() {
        guard let focusedPaneID, let session = sessions[focusedPaneID] else { return }
        session.clear()
    }

    func updateAllWorkingDirectories(to path: String, restartRunning: Bool) {
        for session in sessions.values {
            session.updatePreferredWorkingDirectory(path, restartIfRunning: restartRunning)
        }
    }

    func duplicatePane(_ paneID: UUID, defaultWorkingDirectory: String) -> UUID? {
        guard let session = sessions[paneID] else { return nil }
        let snapshot = PaneSnapshot(
            id: UUID(),
            preferredWorkingDirectory: session.preferredWorkingDirectory,
            preferredEngine: session.requestedEngine,
            backendConfiguration: session.backendConfiguration
        )
        let duplicated = ShellSession(snapshot: snapshot)
        sessions[snapshot.id] = duplicated
        focusedPaneID = snapshot.id
        duplicated.startIfNeeded()
        return snapshot.id
    }

    func sessionSnapshots(in paneOrder: [UUID]) -> [PaneSnapshot] {
        paneOrder.compactMap { sessions[$0]?.snapshot() }
    }

    func hasActiveSession(using path: String) -> Bool {
        sessions.values.contains(where: { $0.hasActiveProcess && $0.isUsing(pathPrefix: path) })
    }

    func activeSessionCount(using path: String) -> Int {
        sessions.values.filter { $0.hasActiveProcess && $0.isUsing(pathPrefix: path) }.count
    }

    func runningSessionCount(using path: String) -> Int {
        sessions.values.filter { $0.isRunning && $0.isUsing(pathPrefix: path) }.count
    }

    private func updateSessionFocusStates() {
        for (paneID, session) in sessions {
            session.setFocused(paneID == focusedPaneID)
        }
    }
}
