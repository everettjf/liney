//
//  LineyDesktopApplication+ControlHost.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

/// Glue between the IPC dispatcher and the live application state.
///
/// Each handler converts a wire-shape request into a real action against
/// the desktop application or its workspace stores. Most actions are
/// synchronous from the caller's perspective; long-running operations
/// (e.g. `openRepositoryWorkspace`) are kicked off as detached Tasks and
/// reflected to the user via the sidebar / `liney session list`.
extension LineyDesktopApplication: LineyControlHost {
    func handleNotify(_ request: AgentNotifyRequest) {
        routeAgentNotification(request)
    }

    func handleOpen(_ request: LineyOpenRequest) -> LineyControlResponse {
        guard let store = activeWorkspaceStore else {
            return .failure("no-active-window")
        }
        let path = request.repo
        let worktreePath = request.worktree
        Task { @MainActor in
            do {
                try await store.openRepositoryWorkspace(at: path, persistAfterChange: true)
                if let worktreePath,
                   let workspace = store.workspaces.first(where: {
                       $0.supportsRepositoryFeatures && $0.repositoryRoot == path
                   }),
                   workspace.activeWorktreePath != worktreePath {
                    workspace.switchToWorktree(path: worktreePath, restartRunning: false)
                }
            } catch {
                NSLog("[Liney] control open failed: %@", String(describing: error))
            }
        }
        return .success
    }

    func handleSplit(_ request: LineySplitRequest) -> LineyControlResponse {
        let axis: PaneSplitAxis = (request.axis?.lowercased() == "horizontal") ? .horizontal : .vertical

        if let paneIDString = request.pane, let paneID = UUID(uuidString: paneIDString) {
            for store in allWorkspaceStores {
                for workspace in store.workspaces
                where workspace.sessionController.session(for: paneID) != nil {
                    workspace.sessionController.focusedPaneID = paneID
                    store.splitFocusedPane(in: workspace, axis: axis)
                    return .success
                }
            }
            return .failure("pane-not-found")
        }

        splitFocusedPane(axis: axis)
        return .success
    }

    func handleSendKeys(_ request: LineySendKeysRequest) -> LineyControlResponse {
        let resolvedPane: UUID?
        if let paneIDString = request.pane, let paneID = UUID(uuidString: paneIDString) {
            resolvedPane = paneID
        } else {
            resolvedPane = activeWorkspaceStore?.selectedWorkspace?.sessionController.focusedPaneID
        }
        guard let resolvedPane else {
            return .failure("no-pane")
        }
        for store in allWorkspaceStores {
            for workspace in store.workspaces {
                if let session = workspace.sessionController.session(for: resolvedPane) {
                    session.insertText(request.text)
                    return .success
                }
            }
        }
        return .failure("pane-not-found")
    }

    func handleSessionList(_ request: LineySessionListRequest) -> LineyControlResponse {
        var sessions: [LineyControlSession] = []
        for store in allWorkspaceStores {
            for workspace in store.workspaces where workspace.isActive {
                for (paneID, session) in workspace.sessionController.sessions {
                    sessions.append(
                        LineyControlSession(
                            workspaceID: workspace.id.uuidString.lowercased(),
                            workspaceName: workspace.name,
                            paneID: paneID.uuidString.lowercased(),
                            cwd: session.effectiveWorkingDirectory,
                            branch: workspace.supportsRepositoryFeatures ? workspace.currentBranch : nil,
                            listeningPorts: workspace.listeningPorts
                        )
                    )
                }
            }
        }
        return LineyControlResponse(ok: true, error: nil, sessions: sessions)
    }
}
