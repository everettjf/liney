//
//  SSHConfigService.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

/// Status of an SSH connection test.
enum SSHConnectionStatus {
    case connected
    case authRequired
    case unreachable(Error)
}

/// Service that loads SSH configuration entries and tests connections.
actor SSHConfigService {
    private var cachedEntries: [SSHConfigEntry] = []
    private let runner = ShellCommandRunner()

    /// Load SSH config entries from the given paths, caching the result.
    func loadSSHConfig(configPaths: [String] = ["~/.ssh/config"]) -> [SSHConfigEntry] {
        var allEntries: [SSHConfigEntry] = []
        for path in configPaths {
            allEntries.append(contentsOf: SSHConfigParser.parse(configPath: path))
        }
        cachedEntries = allEntries
        return allEntries
    }

    /// Test whether an SSH connection can be established to the given entry.
    ///
    /// Uses `/usr/bin/ssh` with `BatchMode=yes` so that interactive password
    /// prompts are suppressed.  Returns `.connected` when the remote echoes
    /// the expected marker, `.authRequired` when the SSH process exits
    /// non-zero (typically a key-auth failure), and `.unreachable` when the
    /// command itself throws (e.g. executable not found, timeout).
    func testConnection(_ entry: SSHConfigEntry) async -> SSHConnectionStatus {
        var arguments: [String] = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            "-o", "StrictHostKeyChecking=accept-new",
        ]

        if let user = entry.user {
            arguments.append(contentsOf: ["-l", user])
        }

        if entry.port != 22 {
            arguments.append(contentsOf: ["-p", String(entry.port)])
        }

        if let identityFile = entry.identityFile {
            let expandedPath = (identityFile as NSString).expandingTildeInPath
            arguments.append(contentsOf: ["-i", expandedPath])
        }

        arguments.append(entry.host)
        arguments.append("echo __OK__")

        do {
            let result = try await runner.run(
                executable: "/usr/bin/ssh",
                arguments: arguments
            )

            if result.exitCode == 0, result.stdout.contains("__OK__") {
                return .connected
            } else {
                return .authRequired
            }
        } catch {
            return .unreachable(error)
        }
    }
}
