//
//  SFTPService.swift
//  Liney
//
//  Author: everettjf
//

import Foundation
import os

// MARK: - SFTPServiceError

enum SFTPServiceError: LocalizedError, Equatable {
    case notConnected
    case authenticationFailed
    case keyFileNotFound(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to remote host"
        case .authenticationFailed:
            return "SSH authentication failed"
        case .keyFileNotFound(let path):
            return "SSH key file not found: \(path)"
        case .commandFailed(let message):
            return "Remote command failed: \(message)"
        }
    }
}

// MARK: - SFTPService

actor SFTPService {

    private enum ConnectionMode {
        case none
        case ssh(SSHSessionConfiguration)
    }

    private var mode: ConnectionMode = .none
    private let runner = ShellCommandRunner()

    // MARK: - Public API

    /// Connect using system SSH with BatchMode (key-based auth only).
    func connect(target: SSHSessionConfiguration) async throws {
        // Validate identity file if specified
        if let identityFile = target.identityFilePath, !identityFile.isEmpty {
            let expanded = (identityFile as NSString).expandingTildeInPath
            if !FileManager.default.fileExists(atPath: expanded) {
                throw SFTPServiceError.keyFileNotFound(identityFile)
            }
        }

        let result = try await executeRemoteCommand("echo __OK__", target: target)
        guard result.exitCode == 0, result.stdout.contains("__OK__") else {
            throw SFTPServiceError.authenticationFailed
        }
        mode = .ssh(target)
    }

    // TODO: func connectWithPassword(target:password:) — Citadel integration

    /// List directories at the given remote path.
    func listDirectories(at path: String) async throws -> [SFTPDirectoryEntry] {
        let target = try currentTarget()
        let result = try await executeRemoteCommand("ls -1pa \(path.shellQuoted)", target: target)
        guard result.exitCode == 0 else {
            throw SFTPServiceError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let entries = result.stdout
            .components(separatedBy: "\n")
            .filter { line in
                // Keep only directory entries (ending with /)
                guard line.hasSuffix("/") else { return false }
                // Exclude current dir, parent dir, and hidden dirs
                let name = String(line.dropLast()) // remove trailing /
                if name == "." || name == ".." { return false }
                if name.hasPrefix(".") { return false }
                return true
            }
            .map { line -> SFTPDirectoryEntry in
                let name = String(line.dropLast()) // remove trailing /
                let normalizedPath = path.hasSuffix("/") ? path : path + "/"
                return SFTPDirectoryEntry(name: name, path: normalizedPath + name)
            }
            .sorted()

        return entries
    }

    /// Return the home directory on the remote host.
    func homeDirectory() async throws -> String {
        let target = try currentTarget()
        let result = try await executeRemoteCommand("echo $HOME", target: target)
        guard result.exitCode == 0 else {
            throw SFTPServiceError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Disconnect and reset state.
    func disconnect() {
        mode = .none
    }

    // MARK: - Private Helpers

    private func currentTarget() throws -> SSHSessionConfiguration {
        switch mode {
        case .none:
            throw SFTPServiceError.notConnected
        case .ssh(let target):
            return target
        }
    }

    private func executeRemoteCommand(_ command: String, target: SSHSessionConfiguration) async throws -> ShellCommandResult {
        var args: [String] = []

        // SSH options
        args += ["-o", "BatchMode=yes"]
        args += ["-o", "ConnectTimeout=10"]
        args += ["-o", "StrictHostKeyChecking=accept-new"]

        // Port
        if let port = target.port {
            args += ["-p", "\(port)"]
        }

        // Identity file
        if let identityFile = target.identityFilePath, !identityFile.isEmpty {
            let expanded = (identityFile as NSString).expandingTildeInPath
            args += ["-i", expanded]
        }

        // Destination
        args.append(target.destination)

        // Command
        args.append(command)

        return try await runner.run(
            executable: "/usr/bin/ssh",
            arguments: args
        )
    }
}
