//
//  TmuxService.swift
//  Liney
//
//  Author: everettjf
//

import Foundation
import os

struct TmuxSessionInfo: Codable, Identifiable {
    var id: String { name }
    let name: String
    let windowCount: Int
    let isAttached: Bool
    let createdAt: Date?
}

actor TmuxService {
    private let runner = ShellCommandRunner()
    private static let tmuxPath = "/usr/bin/env"
    private static let sshPath = "/usr/bin/ssh"

    private static let listFormat = "#{session_name}\t#{session_windows}\t#{session_attached}\t#{session_created}"

    // MARK: - Local Sessions

    func listLocalSessions() async throws -> [TmuxSessionInfo] {
        let result = try await runner.run(
            executable: Self.tmuxPath,
            arguments: ["tmux", "list-sessions", "-F", Self.listFormat]
        )

        if result.exitCode != 0 {
            // Exit code 1 with "no server running" means no sessions
            if result.stderr.contains("no server running") || result.stderr.contains("no sessions") {
                return []
            }
            throw ShellCommandError.failed("tmux list-sessions failed: \(result.stderr)")
        }

        return Self.parseSessions(result.stdout)
    }

    // MARK: - Remote Sessions

    func listRemoteSessions(_ sshConfig: SSHSessionConfiguration) async throws -> [TmuxSessionInfo] {
        var sshArgs = buildSSHArguments(for: sshConfig)
        sshArgs.append("tmux list-sessions -F '\(Self.listFormat)'")

        let result = try await runner.run(
            executable: Self.sshPath,
            arguments: sshArgs
        )

        if result.exitCode != 0 {
            if result.stderr.contains("no server running") || result.stderr.contains("no sessions") {
                return []
            }
            throw ShellCommandError.failed("Remote tmux list-sessions failed: \(result.stderr)")
        }

        return Self.parseSessions(result.stdout)
    }

    // MARK: - Session Status

    func isSessionAlive(name: String) async -> Bool {
        do {
            let result = try await runner.run(
                executable: Self.tmuxPath,
                arguments: ["tmux", "has-session", "-t", name]
            )
            return result.exitCode == 0
        } catch {
            return false
        }
    }

    // MARK: - Attach Commands

    nonisolated func attachCommand(for sessionName: String) -> String {
        "tmux attach-session -t \(sessionName.shellQuoted)"
    }

    nonisolated func remoteAttachCommand(for sessionName: String, via sshConfig: SSHSessionConfiguration) -> String {
        var parts = ["ssh"]

        if let port = sshConfig.port, port != 22 {
            parts.append("-p \(port)")
        }

        if let identityFilePath = sshConfig.identityFilePath, !identityFilePath.isEmpty {
            parts.append("-i \(identityFilePath.shellQuoted)")
        }

        parts.append("-t")
        parts.append(sshConfig.destination)
        parts.append("tmux attach-session -t \(sessionName.shellQuoted)")

        return parts.joined(separator: " ")
    }

    // MARK: - Parsing

    static func parseSessions(_ output: String) -> [TmuxSessionInfo] {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
        return lines.compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 4 else { return nil }

            let name = String(fields[0])
            guard !name.isEmpty else { return nil }

            guard let windowCount = Int(fields[1]) else { return nil }
            let isAttached = fields[2] == "1"

            var createdAt: Date?
            if let timestamp = TimeInterval(String(fields[3])) {
                createdAt = Date(timeIntervalSince1970: timestamp)
            }

            return TmuxSessionInfo(
                name: name,
                windowCount: windowCount,
                isAttached: isAttached,
                createdAt: createdAt
            )
        }
    }

    // MARK: - Private Helpers

    private func buildSSHArguments(for config: SSHSessionConfiguration) -> [String] {
        var args: [String] = []

        if let port = config.port, port != 22 {
            args.append(contentsOf: ["-p", "\(port)"])
        }

        if let identityFilePath = config.identityFilePath, !identityFilePath.isEmpty {
            args.append(contentsOf: ["-i", identityFilePath])
        }

        args.append(config.destination)
        return args
    }
}
