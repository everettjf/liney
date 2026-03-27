//
//  SessionBackendLaunch.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

struct TerminalCommandDefinition: Hashable {
    var executablePath: String
    var arguments: [String]
    var displayName: String
}

struct TerminalLaunchConfiguration: Hashable {
    var workingDirectory: String
    var environment: [String: String]
    var command: TerminalCommandDefinition
    var backendConfiguration: SessionBackendConfiguration

    var ghosttyCommand: String {
        ([command.executablePath] + command.arguments)
            .map(\.shellQuoted)
            .joined(separator: " ")
    }
}

extension SessionBackendConfiguration {
    func makeLaunchConfiguration(
        preferredWorkingDirectory: String,
        baseEnvironment: [String: String]
    ) -> TerminalLaunchConfiguration {
        switch kind {
        case .localShell:
            let local = localShellConfiguration
            let command = TerminalCommandDefinition(
                executablePath: local.shellPath,
                arguments: local.shellArguments,
                displayName: URL(fileURLWithPath: local.shellPath).lastPathComponent
            )
            let prepared = LineyGhosttyShellIntegration.prepare(
                command: command,
                environment: baseEnvironment
            )
            return TerminalLaunchConfiguration(
                workingDirectory: preferredWorkingDirectory,
                environment: prepared.environment,
                command: prepared.command,
                backendConfiguration: self
            )

        case .ssh:
            let configuration = ssh ?? SSHSessionConfiguration(
                host: "localhost",
                user: nil,
                port: nil,
                identityFilePath: nil,
                remoteWorkingDirectory: nil,
                remoteCommand: nil
            )
            return TerminalLaunchConfiguration(
                workingDirectory: NSHomeDirectory(),
                environment: baseEnvironment,
                command: TerminalCommandDefinition(
                    executablePath: "/usr/bin/ssh",
                    arguments: configuration.sshArguments(),
                    displayName: configuration.destination
                ),
                backendConfiguration: self
            )

        case .agent:
            let configuration = agent ?? AgentSessionConfiguration(
                name: "Agent",
                launchPath: "/usr/bin/env",
                arguments: ["bash", "-lc", "echo 'Agent session is not configured.'; exec /bin/zsh -l"],
                environment: [:],
                workingDirectory: nil
            )
            var environment = baseEnvironment
            for (key, value) in configuration.environment {
                environment[key] = value
            }
            let command = TerminalCommandDefinition(
                executablePath: configuration.launchPath,
                arguments: configuration.arguments,
                displayName: configuration.name
            )
            let prepared = LineyGhosttyShellIntegration.prepare(
                command: command,
                environment: environment
            )
            return TerminalLaunchConfiguration(
                workingDirectory: configuration.workingDirectory ?? preferredWorkingDirectory,
                environment: prepared.environment,
                command: prepared.command,
                backendConfiguration: self
            )
        }
    }
}

private extension SSHSessionConfiguration {
    func sshArguments() -> [String] {
        // Dedicated SSH panes are interactive terminal sessions, so always
        // force a remote PTY to keep line editing and arrow keys working.
        var arguments: [String] = ["-tt"]
        if let port {
            arguments.append(contentsOf: ["-p", String(port)])
        }
        if let identityFilePath, !identityFilePath.isEmpty {
            arguments.append(contentsOf: ["-i", identityFilePath])
        }
        arguments.append(destination)
        if let remoteInvocation = remoteInvocation(), !remoteInvocation.isEmpty {
            arguments.append(remoteInvocation)
        }
        return arguments
    }

    func remoteInvocation() -> String? {
        let remoteShellCommand = normalizedRemoteCommand()
        let remoteWorkingDirectoryCommand = normalizedRemoteWorkingDirectoryCommand()

        switch (remoteWorkingDirectoryCommand, remoteShellCommand) {
        case (.none, .none):
            return nil
        case let (.some(directoryCommand), .none):
            return "\(directoryCommand) && exec ${SHELL:-/bin/zsh} -l"
        case let (.none, .some(shellCommand)):
            return shellCommand
        case let (.some(directoryCommand), .some(shellCommand)):
            return "\(directoryCommand) && \(shellCommand)"
        }
    }

    func normalizedRemoteCommand() -> String? {
        guard let remoteCommand, !remoteCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return remoteCommand
    }

    func normalizedRemoteWorkingDirectoryCommand() -> String? {
        guard let remoteWorkingDirectory, !remoteWorkingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return "cd \(remoteWorkingDirectory.shellQuoted)"
    }
}
