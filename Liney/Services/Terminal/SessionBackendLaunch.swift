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
    var initialInput: String?

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
                backendConfiguration: self,
                initialInput: nil
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
                backendConfiguration: self,
                initialInput: configuration.initialInput
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
                backendConfiguration: self,
                initialInput: nil
            )

        case .tmuxAttach:
            let configuration = tmuxAttach ?? TmuxAttachConfiguration(
                sessionName: "default",
                windowIndex: nil,
                isRemote: false,
                sshConfig: nil
            )
            let tmuxTarget: String = {
                if let windowIndex = configuration.windowIndex {
                    return "\(configuration.sessionName.shellQuoted):\(windowIndex)"
                }
                return configuration.sessionName.shellQuoted
            }()

            if configuration.isRemote, let sshConfig = configuration.sshConfig {
                var sshArgs: [String] = ["-t"]
                if let port = sshConfig.port {
                    sshArgs.append(contentsOf: ["-p", String(port)])
                }
                if let identityFilePath = sshConfig.identityFilePath, !identityFilePath.isEmpty {
                    sshArgs.append(contentsOf: ["-i", identityFilePath])
                }
                sshArgs.append(sshConfig.destination)
                sshArgs.append("tmux attach-session -t \(tmuxTarget)")

                return TerminalLaunchConfiguration(
                    workingDirectory: NSHomeDirectory(),
                    environment: baseEnvironment,
                    command: TerminalCommandDefinition(
                        executablePath: "/usr/bin/ssh",
                        arguments: sshArgs,
                        displayName: "tmux: \(configuration.sessionName)"
                    ),
                    backendConfiguration: self,
                    initialInput: nil
                )
            } else {
                let shellPath = LocalShellSessionConfiguration.default.shellPath
                return TerminalLaunchConfiguration(
                    workingDirectory: NSHomeDirectory(),
                    environment: baseEnvironment,
                    command: TerminalCommandDefinition(
                        executablePath: shellPath,
                        arguments: ["--login", "-c", "exec tmux attach-session -t \(tmuxTarget)"],
                        displayName: "tmux: \(configuration.sessionName)"
                    ),
                    backendConfiguration: self,
                    initialInput: nil
                )
            }
        }
    }
}

private extension SSHSessionConfiguration {
    func sshArguments() -> [String] {
        // Dedicated SSH panes are interactive terminal sessions, so always
        // force a remote PTY to keep line editing and arrow keys working.
        var arguments: [String] = ["-tt"]
        arguments.append(contentsOf: [
            "-o", "SetEnv COLORTERM=truecolor",
            "-o", "SendEnv TERM_PROGRAM TERM_PROGRAM_VERSION",
        ])
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

    var initialInput: String? {
        guard normalizedRemoteCommand() == nil else { return nil }

        let commands = sshBootstrapCommands()
        guard !commands.isEmpty else { return nil }

        return commands.joined(separator: "\n") + "\n"
    }

    func remoteInvocation() -> String? {
        let remoteShellCommand = normalizedRemoteCommand()
        let remoteWorkingDirectoryCommand = normalizedRemoteWorkingDirectoryCommand()

        switch (remoteWorkingDirectoryCommand, remoteShellCommand) {
        case (.none, .none):
            return nil
        case (.some, .none):
            return nil
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

    func sshBootstrapCommands() -> [String] {
        var commands = [
            #"tmux set-option -g set-titles on 2>/dev/null; true"#,
            #"if [ -n "$ZSH_VERSION" ]; then bindkey $'\e[1;3D' backward-word 2>/dev/null; bindkey $'\e[1;3C' forward-word 2>/dev/null; bindkey $'\e\e[D' backward-word 2>/dev/null; bindkey $'\e\e[C' forward-word 2>/dev/null; fi"#,
            #"if [ -n "$BASH_VERSION" ]; then bind '"\e[1;3D": backward-word' 2>/dev/null; bind '"\e[1;3C": forward-word' 2>/dev/null; bind '"\e\e[D": backward-word' 2>/dev/null; bind '"\e\e[C": forward-word' 2>/dev/null; fi"#,
        ]

        if let remoteWorkingDirectoryCommand = normalizedRemoteWorkingDirectoryCommand() {
            commands.append(remoteWorkingDirectoryCommand)
        }

        return commands
    }
}
