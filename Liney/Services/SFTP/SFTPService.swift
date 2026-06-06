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

    /// Per-user directory holding SSH control sockets. Kept short (the socket
    /// path must fit in `sun_path`, ~104 chars) and user-only (`0700`).
    private static let controlDirectory: String = {
        let dir = "/tmp/liney-ssh-\(getuid())"
        try? FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return dir
    }()

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

    /// List files and directories at the given remote path.
    ///
    /// Unlike `listDirectories`, this returns both files and directories with an
    /// `isDirectory` flag, and honors `includesHidden` (always dropping `.`/`..`).
    /// Directories sort before files, then case-insensitively by name.
    func listEntries(at path: String, includesHidden: Bool) async throws -> [SFTPFileEntry] {
        let target = try currentTarget()
        // `-p` appends `/` to directories; `-L` dereferences symlinks so a link
        // pointing at a directory is also marked with `/` (not shown as a file);
        // `-a` adds hidden entries (omitting it lets `ls` exclude dotfiles).
        let command = includesHidden ? "ls -1paL \(path.shellQuoted)" : "ls -1pL \(path.shellQuoted)"
        let result = try await executeRemoteCommand(command, target: target)
        // `ls` exits non-zero on partial errors (e.g. a broken symlink) while
        // still listing the rest on stdout. Only treat it as a hard failure
        // when there is nothing to show.
        guard result.exitCode == 0 || !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SFTPServiceError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let base = path.hasSuffix("/") ? path : path + "/"
        return result.stdout
            .components(separatedBy: "\n")
            .compactMap { line -> SFTPFileEntry? in
                guard !line.isEmpty else { return nil }
                let isDirectory = line.hasSuffix("/")
                let name = isDirectory ? String(line.dropLast()) : line
                guard name != ".", name != "..", !name.isEmpty else { return nil }
                return SFTPFileEntry(name: name, path: base + name, isDirectory: isDirectory)
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory && !rhs.isDirectory
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
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

        // When a Keychain password is configured, authenticate through the
        // SSH_ASKPASS helper. BatchMode would disable that path, so we drop it
        // and cap the prompt count to fail fast on a wrong stored password.
        let askpassEnvironment = SSHPasswordStore.askpassEnvironment(account: target.passwordKeychainAccount)

        // SSH options
        if askpassEnvironment == nil {
            args += ["-o", "BatchMode=yes"]
        } else {
            args += ["-o", "NumberOfPasswordPrompts=1"]
        }
        args += ["-o", "ConnectTimeout=10"]
        args += ["-o", "StrictHostKeyChecking=accept-new"]

        // Connection multiplexing: the first command opens a master connection
        // and later ones (e.g. expanding the file tree) reuse it instead of
        // paying a full SSH handshake each time. `%C` keys the socket per
        // host/port/user. The master lingers briefly after the last command.
        args += ["-o", "ControlMaster=auto"]
        args += ["-o", "ControlPath=\(Self.controlDirectory)/%C"]
        args += ["-o", "ControlPersist=60"]

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
            arguments: args,
            environment: askpassEnvironment
        )
    }
}
