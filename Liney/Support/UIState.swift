//
//  UIState.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

enum LineyFeatureFlags {
    static let showsRemoteSessionCreationUI = true
}

struct PresentedError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

enum WorkspaceStatusTone {
    case neutral
    case success
    case warning
}

struct WorkspaceStatusMessage: Identifiable {
    let id = UUID()
    let text: String
    let tone: WorkspaceStatusTone
}

struct WorkspaceSettingsRequest: Identifiable {
    let id = UUID()
    let workspaceID: UUID?
}

struct QuickCommandEditorRequest: Identifiable {
    let id = UUID()
}

struct WorkflowEditorRequest: Identifiable {
    let id = UUID()
    let workspaceID: UUID
}

struct WorkspaceFileBrowserRequest: Identifiable {
    let id = UUID()
    let workspaceID: UUID
    let workspaceName: String
    let rootPath: String
}

enum SidebarIconCustomizationTarget: Hashable {
    case workspace(UUID)
    case worktree(workspaceID: UUID, worktreePath: String)
    case workspaceGroup(UUID)
    case appDefaultRepository
    case appDefaultLocalTerminal
    case appDefaultWorktree
}

struct SidebarIconCustomizationRequest: Identifiable {
    let id = UUID()
    let target: SidebarIconCustomizationTarget
}

struct RenameWorkspaceRequest: Identifiable {
    let id = UUID()
    let workspaceID: UUID
    let currentName: String
    var isGroupCreation: Bool = false
    var isGroupRename: Bool = false
    var groupID: UUID?
    var groupWorkspaceIDs: [UUID] = []
}

struct CreateWorktreeSheetRequest: Identifiable {
    let id = UUID()
    let workspaceID: UUID
    let workspaceName: String
    let repositoryRoot: String
    var isRemote: Bool = false
}

struct CreateSSHSessionRequest: Identifiable {
    let id = UUID()
    let workspaceID: UUID
    let workspaceName: String
    let defaultWorkingDirectory: String
    let remoteTargets: [RemoteWorkspaceTarget]
    let presets: [SSHPreset]
    let preferredPresetID: UUID?
}

struct CreateAgentSessionRequest: Identifiable {
    // TODO: Keep the request models wired while the UI entry points stay hidden behind the feature flag above.
    let id = UUID()
    let workspaceID: UUID
    let workspaceName: String
    let defaultWorkingDirectory: String
    let presets: [AgentPreset]
    let preferredPresetID: UUID?
}

struct CreateRemoteWorkspaceRequest: Identifiable {
    let id = UUID()
}

struct PendingWorktreeSwitch: Identifiable {
    let id = UUID()
    let workspaceID: UUID
    let targetPath: String
    let targetName: String
    let runningPaneCount: Int
    let requestedAction: PendingWorktreeAction
}

struct PendingWorktreeRemoval: Identifiable {
    let id = UUID()
    let workspaceID: UUID
    let worktreePaths: [String]
    let worktreeNames: [String]
    let activePaneCount: Int
    let includesActiveWorktree: Bool
    let dirtyWorktreeNames: [String]
    let dirtyFileCount: Int
    let aheadWorktreeNames: [String]
    let aheadCommitCount: Int

    var itemCount: Int {
        worktreePaths.count
    }

    var summaryName: String {
        if itemCount == 1 {
            return worktreeNames.first ?? LocalizationManager.shared.string("main.worktreeRemoval.summaryFallback")
        }
        return l10nFormat(
            LocalizationManager.shared.string("main.worktreeRemoval.summaryFormat"),
            arguments: [itemCount]
        )
    }

    var allowsForceRemove: Bool {
        dirtyFileCount > 0
    }

    var detailMessage: String {
        var parts = [
            l10nFormat(
                LocalizationManager.shared.string("main.worktreeRemoval.detail.removeFormat"),
                arguments: [summaryName]
            )
        ]

        if includesActiveWorktree {
            parts.append(LocalizationManager.shared.string("main.worktreeRemoval.detail.switchBack"))
        }
        if activePaneCount > 0 {
            parts.append(
                l10nFormat(
                    LocalizationManager.shared.string("main.worktreeRemoval.detail.terminatePanesFormat"),
                    arguments: [activePaneCount]
                )
            )
        }
        if dirtyFileCount > 0 {
            parts.append(
                l10nFormat(
                    LocalizationManager.shared.string("main.worktreeRemoval.detail.dirtyFormat"),
                    arguments: [formattedNames(dirtyWorktreeNames), dirtyFileCount]
                )
            )
        }
        if aheadCommitCount > 0 {
            parts.append(
                l10nFormat(
                    LocalizationManager.shared.string("main.worktreeRemoval.detail.aheadFormat"),
                    arguments: [formattedNames(aheadWorktreeNames), aheadCommitCount]
                )
            )
        }

        return parts.joined(separator: " ")
    }

    private func formattedNames(_ names: [String]) -> String {
        let uniqueNames = Array(Set(names)).sorted()
        if uniqueNames.isEmpty {
            return LocalizationManager.shared.string("main.worktreeRemoval.names.selected")
        }
        if uniqueNames.count == 1 {
            return uniqueNames[0]
        }
        if uniqueNames.count == 2 {
            return l10nFormat(
                LocalizationManager.shared.string("main.worktreeRemoval.names.twoFormat"),
                arguments: [uniqueNames[0], uniqueNames[1]]
            )
        }
        return l10nFormat(
            LocalizationManager.shared.string("main.worktreeRemoval.names.moreFormat"),
            arguments: [uniqueNames[0], uniqueNames[1], uniqueNames.count - 2]
        )
    }
}

struct EditWorktreeNoteRequest: Identifiable {
    let id = UUID()
    let workspaceID: UUID
    let worktreePath: String
    var currentNote: String
}

struct CreateWorktreeDraft {
    var directoryPath: String = ""
    var branchName: String = ""
    var createNewBranch: Bool = true

    var normalizedBranchName: String {
        branchName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedDirectoryPath: String {
        directoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct CreateSSHSessionDraft {
    var selectedTargetID: UUID? = nil
    var selectedPresetID: UUID? = nil
    var selectedAgentPresetID: UUID? = nil
    var saveAsTarget: Bool = false
    var targetName: String = ""
    var host: String = ""
    var user: String = ""
    var port: String = ""
    var identityFilePath: String = ""
    var remoteWorkingDirectory: String = ""
    var remoteCommand: String = ""

    var normalizedTargetName: String {
        targetName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var configuration: SSHSessionConfiguration? {
        let host = normalizedHost
        guard !host.isEmpty else { return nil }
        return SSHSessionConfiguration(
            host: host,
            user: user.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            port: Int(port.trimmingCharacters(in: .whitespacesAndNewlines)),
            identityFilePath: identityFilePath.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            remoteWorkingDirectory: remoteWorkingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            remoteCommand: remoteCommand.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
    }

    var targetToSave: RemoteWorkspaceTarget? {
        guard saveAsTarget,
              let configuration,
              let name = normalizedTargetName.nilIfEmpty else {
            return nil
        }
        return RemoteWorkspaceTarget(
            id: selectedTargetID ?? UUID(),
            name: name,
            ssh: configuration,
            sshPresetID: selectedPresetID,
            agentPresetID: selectedAgentPresetID
        )
    }

    mutating func apply(sshPreset: SSHPreset, defaultWorkingDirectory: String) {
        selectedTargetID = nil
        selectedAgentPresetID = nil
        selectedPresetID = sshPreset.id
        host = sshPreset.host ?? ""
        user = sshPreset.user ?? ""
        port = sshPreset.port.map(String.init) ?? ""
        identityFilePath = sshPreset.identityFilePath ?? ""
        remoteWorkingDirectory = sshPreset.remoteWorkingDirectory ?? defaultWorkingDirectory
        remoteCommand = sshPreset.remoteCommand
    }

    mutating func apply(remoteTarget: RemoteWorkspaceTarget) {
        selectedTargetID = remoteTarget.id
        selectedPresetID = remoteTarget.sshPresetID
        selectedAgentPresetID = remoteTarget.agentPresetID
        targetName = remoteTarget.name
        host = remoteTarget.ssh.host
        user = remoteTarget.ssh.user ?? ""
        if let port = remoteTarget.ssh.port {
            self.port = String(port)
        } else {
            port = ""
        }
        identityFilePath = remoteTarget.ssh.identityFilePath ?? ""
        remoteWorkingDirectory = remoteTarget.ssh.remoteWorkingDirectory ?? ""
        remoteCommand = remoteTarget.ssh.remoteCommand ?? ""
    }
}

struct CreateAgentSessionDraft {
    var selectedPresetID: UUID? = AgentPreset.claudeCode.id
    var name: String = AgentPreset.claudeCode.name
    var launchPath: String = "/usr/bin/env"
    var argumentsText: String = "claude"
    var environmentText: String = ""
    var workingDirectory: String = ""
    var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? AgentPreset.claudeCode.name
    }

    var normalizedLaunchPath: String {
        launchPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedWorkingDirectory: String? {
        workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var arguments: [String] {
        argumentsText
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var environment: [String: String] {
        environmentText
            .split(whereSeparator: \.isNewline)
            .reduce(into: [:]) { result, line in
                let value = String(line)
                guard let separatorIndex = value.firstIndex(of: "=") else { return }
                let key = String(value[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                let environmentValue = String(value[value.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { return }
                result[key] = environmentValue
            }
    }

    var configuration: AgentSessionConfiguration? {
        let launchPath = normalizedLaunchPath
        guard !launchPath.isEmpty else { return nil }
        return AgentSessionConfiguration(
            name: normalizedName,
            launchPath: launchPath,
            arguments: arguments,
            environment: environment,
            workingDirectory: normalizedWorkingDirectory
        )
    }

    mutating func apply(preset: AgentPreset) {
        selectedPresetID = preset.id
        name = preset.name
        launchPath = preset.launchPath
        argumentsText = preset.arguments.joined(separator: "\n")
        environmentText = preset.environment
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n")
        workingDirectory = preset.workingDirectory ?? ""
    }
}

enum PendingWorktreeAction: String, Codable {
    case none
    case newSession
    case splitVertical
    case splitHorizontal

    var displayLabel: String {
        switch self {
        case .none:
            return LocalizationManager.shared.string("main.worktreeAction.none")
        case .newSession:
            return LocalizationManager.shared.string("main.worktreeAction.newSession")
        case .splitVertical:
            return LocalizationManager.shared.string("main.worktreeAction.splitVertical")
        case .splitHorizontal:
            return LocalizationManager.shared.string("main.worktreeAction.splitHorizontal")
        }
    }
}
