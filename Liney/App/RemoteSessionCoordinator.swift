//
//  RemoteSessionCoordinator.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

private func lineyLocalizedRemoteString(_ key: String) -> String {
    LocalizationManager.shared.string(key)
}

enum RemoteSessionCoordinatorError: LocalizedError {
    case missingTarget
    case missingAgentPreset

    var errorDescription: String? {
        switch self {
        case .missingTarget:
            return lineyLocalizedRemoteString("remote.error.missingTarget")
        case .missingAgentPreset:
            return lineyLocalizedRemoteString("remote.error.missingAgentPreset")
        }
    }
}

struct RemoteSessionLaunchPlan {
    let backendConfiguration: SessionBackendConfiguration
    let workingDirectory: String
    let activityKind: WorkspaceActivityKind
    let activityTitle: String
    let activityDetail: String
    let replayAction: WorkspaceReplayAction
}

struct RemoteSessionCoordinator {
    @MainActor
    func shellPlan(workspace: WorkspaceModel, targetID: UUID) throws -> RemoteSessionLaunchPlan {
        guard let target = workspace.remoteTargets.first(where: { $0.id == targetID }) else {
            throw RemoteSessionCoordinatorError.missingTarget
        }

        let backendConfiguration = SessionBackendConfiguration.ssh(target.ssh)
        return RemoteSessionLaunchPlan(
            backendConfiguration: backendConfiguration,
            workingDirectory: workspace.activeWorktreePath,
            activityKind: .remote,
            activityTitle: lineyLocalizedRemoteString("remote.activity.openedShell"),
            activityDetail: "\(target.name) · \(target.ssh.destination)",
            replayAction: .createSession(
                backendConfiguration: backendConfiguration,
                workingDirectory: workspace.activeWorktreePath
            )
        )
    }

    @MainActor
    func agentPlan(workspace: WorkspaceModel, targetID: UUID) throws -> RemoteSessionLaunchPlan {
        guard let target = workspace.remoteTargets.first(where: { $0.id == targetID }) else {
            throw RemoteSessionCoordinatorError.missingTarget
        }
        guard let presetID = target.agentPresetID,
              let preset = workspace.agentPresets.first(where: { $0.id == presetID }) else {
            throw RemoteSessionCoordinatorError.missingAgentPreset
        }

        var configuration = target.ssh
        configuration.remoteCommand = Self.remoteAgentCommand(for: preset, target: target)
        let backendConfiguration = SessionBackendConfiguration.ssh(configuration)

        return RemoteSessionLaunchPlan(
            backendConfiguration: backendConfiguration,
            workingDirectory: workspace.activeWorktreePath,
            activityKind: .agent,
            activityTitle: lineyLocalizedRemoteString("remote.activity.openedAgent"),
            activityDetail: "\(target.name) · \(preset.name)",
            replayAction: .createSession(
                backendConfiguration: backendConfiguration,
                workingDirectory: workspace.activeWorktreePath
            )
        )
    }

    @MainActor
    func repositoryBrowserPlan(workspace: WorkspaceModel, targetID: UUID) throws -> RemoteSessionLaunchPlan {
        guard let target = workspace.remoteTargets.first(where: { $0.id == targetID }) else {
            throw RemoteSessionCoordinatorError.missingTarget
        }

        var configuration = target.ssh
        configuration.remoteCommand = Self.remoteRepositoryBrowserCommand(for: target)
        let backendConfiguration = SessionBackendConfiguration.ssh(configuration)

        return RemoteSessionLaunchPlan(
            backendConfiguration: backendConfiguration,
            workingDirectory: workspace.activeWorktreePath,
            activityKind: .remote,
            activityTitle: lineyLocalizedRemoteString("remote.activity.browsedRepository"),
            activityDetail: "\(target.name) · \(target.ssh.destination)",
            replayAction: .createSession(
                backendConfiguration: backendConfiguration,
                workingDirectory: workspace.activeWorktreePath
            )
        )
    }

    nonisolated static func remoteAgentCommand(for preset: AgentPreset, target: RemoteWorkspaceTarget) -> String {
        let launch = ([preset.launchPath] + preset.arguments).map(\.shellQuoted).joined(separator: " ")
        let workingDirectory = preset.workingDirectory ?? target.ssh.remoteWorkingDirectory
        if let workingDirectory, !workingDirectory.isEmpty {
            return "cd \(workingDirectory.shellQuoted) && exec \(launch)"
        }
        return "exec \(launch)"
    }

    nonisolated static func remoteRepositoryBrowserCommand(for target: RemoteWorkspaceTarget) -> String {
        let overview = [
            "pwd",
            "printf '\\n'",
            "ls -la",
            "printf '\\n'",
            "git status --short --branch || true",
            "printf '\\n'",
            "exec ${SHELL:-/bin/zsh} -l"
        ].joined(separator: " && ")

        if let workingDirectory = target.ssh.remoteWorkingDirectory,
           !workingDirectory.isEmpty {
            return "cd \(workingDirectory.shellQuoted) && \(overview)"
        }
        return overview
    }
}
