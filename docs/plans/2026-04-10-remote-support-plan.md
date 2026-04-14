# Remote Server Support Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add comprehensive remote server support to Liney — SSH config parsing, connection testing, SFTP browsing, tmux auto-detection/restoration, remote git inspection, periodic refresh, and a dedicated remote workspace creation UI.

**Architecture:** Layered incremental — foundation services first (SSH, Tmux, SFTP), then data model extensions, then terminal integration, then UI. Each layer is independently testable. Reference implementation: `/Users/yanu/Documents/code/Terminal/treemux`.

**Tech Stack:** Swift, SwiftUI, AppKit, GhosttyKit, Citadel (SSH2 library for SFTP password fallback), system `/usr/bin/ssh`

---

## Task 1: SSH Config Parser

**Files:**
- Create: `Liney/Services/SSH/SSHConfigParser.swift`
- Test: `Tests/SSHConfigParserTests.swift`

**Step 1: Write the test file**

```swift
// Tests/SSHConfigParserTests.swift
import XCTest
@testable import Liney

final class SSHConfigParserTests: XCTestCase {

    func testParsesBasicHostEntry() {
        let config = """
        Host myserver
            HostName 192.168.1.100
            Port 2222
            User deploy
            IdentityFile ~/.ssh/id_ed25519
        """
        let targets = SSHConfigParser.parse(from: config)
        XCTAssertEqual(targets.count, 1)
        let t = targets[0]
        XCTAssertEqual(t.displayName, "myserver")
        XCTAssertEqual(t.host, "192.168.1.100")
        XCTAssertEqual(t.port, 2222)
        XCTAssertEqual(t.user, "deploy")
        XCTAssertEqual(t.identityFile, "~/.ssh/id_ed25519")
    }

    func testUsesHostAsHostNameWhenHostNameMissing() {
        let config = """
        Host direct.example.com
            User admin
        """
        let targets = SSHConfigParser.parse(from: config)
        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets[0].host, "direct.example.com")
    }

    func testFiltersWildcardHosts() {
        let config = """
        Host *
            ServerAliveInterval 60

        Host prod-?
            User root

        Host realserver
            HostName 10.0.0.1
        """
        let targets = SSHConfigParser.parse(from: config)
        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets[0].displayName, "realserver")
    }

    func testParsesMultipleHosts() {
        let config = """
        Host alpha
            HostName alpha.example.com
            Port 22

        Host beta
            HostName beta.example.com
            Port 3022
            User betauser
        """
        let targets = SSHConfigParser.parse(from: config)
        XCTAssertEqual(targets.count, 2)
        XCTAssertEqual(targets[0].displayName, "alpha")
        XCTAssertEqual(targets[1].displayName, "beta")
        XCTAssertEqual(targets[1].port, 3022)
    }

    func testDefaultPortIs22() {
        let config = """
        Host noport
            HostName example.com
        """
        let targets = SSHConfigParser.parse(from: config)
        XCTAssertEqual(targets[0].port, 22)
    }

    func testEmptyConfigReturnsEmpty() {
        let targets = SSHConfigParser.parse(from: "")
        XCTAssertTrue(targets.isEmpty)
    }

    func testCommentsAndBlankLinesIgnored() {
        let config = """
        # This is a comment
        Host myhost
            # inline comment
            HostName example.com

        """
        let targets = SSHConfigParser.parse(from: config)
        XCTAssertEqual(targets.count, 1)
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Liney.xcodeproj -scheme Liney -only-testing LineyTests/SSHConfigParserTests 2>&1 | tail -20`
Expected: Compilation error — `SSHConfigParser` not defined

**Step 3: Create the SSH config parser model and parser**

First, create the parsed target model. This is separate from the existing `SSHSessionConfiguration` — it represents a raw entry from `~/.ssh/config`:

```swift
// Liney/Services/SSH/SSHConfigParser.swift
import Foundation

/// A parsed SSH host entry from ~/.ssh/config.
struct SSHConfigEntry: Hashable {
    let displayName: String
    let host: String
    let port: Int
    let user: String?
    let identityFile: String?
}

/// Parses OpenSSH config files into structured entries.
enum SSHConfigParser {

    /// Parse SSH config from a string (for testing).
    static func parse(from contents: String) -> [SSHConfigEntry] {
        var entries: [SSHConfigEntry] = []
        var currentAlias: String?
        var hostName: String?
        var port: Int = 22
        var user: String?
        var identityFile: String?

        func flushEntry() {
            guard let alias = currentAlias else { return }
            // Skip wildcard hosts
            guard !alias.contains("*"), !alias.contains("?") else {
                currentAlias = nil
                return
            }
            entries.append(SSHConfigEntry(
                displayName: alias,
                host: hostName ?? alias,
                port: port,
                user: user,
                identityFile: identityFile
            ))
            currentAlias = nil
            hostName = nil
            port = 22
            user = nil
            identityFile = nil
        }

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }

            let keyword = parts[0].lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            switch keyword {
            case "host":
                flushEntry()
                currentAlias = value
            case "hostname":
                hostName = value
            case "port":
                port = Int(value) ?? 22
            case "user":
                user = value
            case "identityfile":
                identityFile = value
            default:
                break
            }
        }
        flushEntry()

        return entries
    }

    /// Parse SSH config from the user's config file.
    static func parse(configPath: String = "~/.ssh/config") -> [SSHConfigEntry] {
        let expandedPath = (configPath as NSString).expandingTildeInPath
        guard let contents = try? String(contentsOfFile: expandedPath, encoding: .utf8) else {
            return []
        }
        return parse(from: contents)
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Liney.xcodeproj -scheme Liney -only-testing LineyTests/SSHConfigParserTests 2>&1 | tail -20`
Expected: All 7 tests PASS

**Step 5: Commit**

```bash
git add Liney/Services/SSH/SSHConfigParser.swift Tests/SSHConfigParserTests.swift
git commit -m "feat: add SSH config parser for ~/.ssh/config"
```

---

## Task 2: SSH Config Service

**Files:**
- Create: `Liney/Services/SSH/SSHConfigService.swift`
- Test: `Tests/SSHConfigServiceTests.swift`

**Step 1: Write the test file**

```swift
// Tests/SSHConfigServiceTests.swift
import XCTest
@testable import Liney

final class SSHConfigServiceTests: XCTestCase {

    func testLoadReturnsEntriesFromParser() async {
        let service = SSHConfigService()
        // This tests the real ~/.ssh/config — just verify it returns without crashing
        let entries = await service.loadSSHConfig()
        // entries may be empty if no config exists, that's OK
        XCTAssertNotNil(entries)
    }

    func testConnectionStatusEnumCases() {
        // Verify the enum exists and has expected cases
        let connected = SSHConnectionStatus.connected
        let authRequired = SSHConnectionStatus.authRequired
        let unreachable = SSHConnectionStatus.unreachable(NSError(domain: "", code: 0))

        switch connected {
        case .connected: break
        default: XCTFail("Expected .connected")
        }
        switch authRequired {
        case .authRequired: break
        default: XCTFail("Expected .authRequired")
        }
        switch unreachable {
        case .unreachable: break
        default: XCTFail("Expected .unreachable")
        }
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Liney.xcodeproj -scheme Liney -only-testing LineyTests/SSHConfigServiceTests 2>&1 | tail -20`
Expected: Compilation error — `SSHConfigService` not defined

**Step 3: Write the SSH config service**

```swift
// Liney/Services/SSH/SSHConfigService.swift
import Foundation

enum SSHConnectionStatus {
    case connected
    case authRequired
    case unreachable(Error)
}

/// Manages loading SSH config and testing connections.
actor SSHConfigService {
    private var cachedEntries: [SSHConfigEntry] = []

    func loadSSHConfig(configPaths: [String] = ["~/.ssh/config"]) -> [SSHConfigEntry] {
        var allEntries: [SSHConfigEntry] = []
        for path in configPaths {
            let parsed = SSHConfigParser.parse(configPath: path)
            allEntries.append(contentsOf: parsed)
        }
        cachedEntries = allEntries
        return allEntries
    }

    func testConnection(_ entry: SSHConfigEntry) async -> SSHConnectionStatus {
        var args = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            "-o", "StrictHostKeyChecking=accept-new",
        ]
        if let user = entry.user {
            args.append(contentsOf: ["-l", user])
        }
        args.append(contentsOf: ["-p", String(entry.port)])
        if let identityFile = entry.identityFile, !identityFile.isEmpty {
            let expanded = (identityFile as NSString).expandingTildeInPath
            args.append(contentsOf: ["-i", expanded])
        }
        args.append(entry.host)
        args.append("echo __OK__")

        do {
            let result = try await ShellCommandRunner.run(
                "/usr/bin/ssh", arguments: args, timeout: 10
            )
            if result.exitCode == 0, result.stdout.contains("__OK__") {
                return .connected
            }
            return .authRequired
        } catch {
            return .unreachable(error)
        }
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Liney.xcodeproj -scheme Liney -only-testing LineyTests/SSHConfigServiceTests 2>&1 | tail -20`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add Liney/Services/SSH/SSHConfigService.swift Tests/SSHConfigServiceTests.swift
git commit -m "feat: add SSH config service with connection testing"
```

---

## Task 3: Tmux Service

**Files:**
- Create: `Liney/Services/Tmux/TmuxService.swift`
- Test: `Tests/TmuxServiceTests.swift`

**Step 1: Write the test file**

```swift
// Tests/TmuxServiceTests.swift
import XCTest
@testable import Liney

final class TmuxServiceTests: XCTestCase {

    func testParseSessionsBasic() async {
        let service = TmuxService()
        let output = "main\t3\t1\t1712345678\ndev\t1\t0\t1712345600\n"
        let sessions = await service.parseSessions(output)
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].name, "main")
        XCTAssertEqual(sessions[0].windowCount, 3)
        XCTAssertTrue(sessions[0].isAttached)
        XCTAssertNotNil(sessions[0].createdAt)
        XCTAssertEqual(sessions[1].name, "dev")
        XCTAssertFalse(sessions[1].isAttached)
    }

    func testParseSessionsEmptyOutput() async {
        let service = TmuxService()
        let sessions = await service.parseSessions("")
        XCTAssertTrue(sessions.isEmpty)
    }

    func testParseSessionsMalformedLine() async {
        let service = TmuxService()
        let output = "incomplete\n\nmain\t2\t0\n"
        let sessions = await service.parseSessions(output)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].name, "main")
    }

    func testAttachCommandFormat() async {
        let service = TmuxService()
        let session = TmuxSessionInfo(name: "dev", windowCount: 2, isAttached: false, createdAt: nil)
        let cmd = await service.attachCommand(for: session)
        XCTAssertEqual(cmd, "tmux attach-session -t dev")
    }

    func testRemoteAttachCommandFormat() async {
        let service = TmuxService()
        let session = TmuxSessionInfo(name: "work", windowCount: 1, isAttached: false, createdAt: nil)
        let ssh = SSHSessionConfiguration(
            host: "example.com", user: "deploy", port: 2222,
            identityFilePath: nil, remoteWorkingDirectory: nil, remoteCommand: nil
        )
        let cmd = await service.remoteAttachCommand(for: session, via: ssh)
        XCTAssertTrue(cmd.contains("ssh"))
        XCTAssertTrue(cmd.contains("-l deploy"))
        XCTAssertTrue(cmd.contains("-p 2222"))
        XCTAssertTrue(cmd.contains("example.com"))
        XCTAssertTrue(cmd.contains("tmux attach-session -t work"))
    }

    func testRemoteAttachCommandDefaultPort() async {
        let service = TmuxService()
        let session = TmuxSessionInfo(name: "test", windowCount: 1, isAttached: false, createdAt: nil)
        let ssh = SSHSessionConfiguration(
            host: "example.com", user: nil, port: nil,
            identityFilePath: nil, remoteWorkingDirectory: nil, remoteCommand: nil
        )
        let cmd = await service.remoteAttachCommand(for: session, via: ssh)
        XCTAssertFalse(cmd.contains("-p "))
        XCTAssertFalse(cmd.contains("-l "))
    }
}
```

**Step 2: Run tests to verify they fail**

Expected: Compilation error — `TmuxService`, `TmuxSessionInfo` not defined

**Step 3: Write the Tmux service**

```swift
// Liney/Services/Tmux/TmuxService.swift
import Foundation

struct TmuxSessionInfo: Codable, Identifiable {
    var id: String { name }
    let name: String
    let windowCount: Int
    let isAttached: Bool
    let createdAt: Date?
}

/// Detects and manages tmux sessions, both local and remote.
actor TmuxService {

    // MARK: - Local Sessions

    func listLocalSessions() async throws -> [TmuxSessionInfo] {
        let result = try await ShellCommandRunner.run(
            "/usr/bin/env", arguments: ["tmux", "list-sessions", "-F",
            "#{session_name}\t#{session_windows}\t#{session_attached}\t#{session_created}"]
        )
        return parseSessions(result.stdout)
    }

    func isSessionAlive(name: String) async -> Bool {
        do {
            let result = try await ShellCommandRunner.run(
                "/usr/bin/env", arguments: ["tmux", "has-session", "-t", name]
            )
            return result.exitCode == 0
        } catch {
            return false
        }
    }

    func attachCommand(for session: TmuxSessionInfo) -> String {
        "tmux attach-session -t \(session.name)"
    }

    // MARK: - Remote Sessions

    func listRemoteSessions(_ sshConfig: SSHSessionConfiguration) async throws -> [TmuxSessionInfo] {
        var sshArgs = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5"]
        if let user = sshConfig.user {
            sshArgs.append(contentsOf: ["-l", user])
        }
        if let port = sshConfig.port {
            sshArgs.append(contentsOf: ["-p", String(port)])
        }
        sshArgs.append(sshConfig.host)
        sshArgs.append("tmux list-sessions -F '#{session_name}\t#{session_windows}\t#{session_attached}\t#{session_created}'")

        let result = try await ShellCommandRunner.run("/usr/bin/ssh", arguments: sshArgs)
        return parseSessions(result.stdout)
    }

    func remoteAttachCommand(for session: TmuxSessionInfo, via sshConfig: SSHSessionConfiguration) -> String {
        var cmd = "ssh"
        if let user = sshConfig.user {
            cmd += " -l \(user)"
        }
        if let port = sshConfig.port, port != 22 {
            cmd += " -p \(port)"
        }
        cmd += " \(sshConfig.host) -t 'tmux attach-session -t \(session.name)'"
        return cmd
    }

    // MARK: - Parsing

    func parseSessions(_ output: String) -> [TmuxSessionInfo] {
        var sessions: [TmuxSessionInfo] = []
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.components(separatedBy: "\t")
            guard parts.count >= 3 else { continue }

            let name = parts[0]
            let windowCount = Int(parts[1]) ?? 0
            let isAttached = parts[2] == "1"
            var createdAt: Date?
            if parts.count >= 4, let timestamp = TimeInterval(parts[3]) {
                createdAt = Date(timeIntervalSince1970: timestamp)
            }
            sessions.append(TmuxSessionInfo(
                name: name, windowCount: windowCount,
                isAttached: isAttached, createdAt: createdAt
            ))
        }
        return sessions
    }
}
```

**Step 4: Run tests to verify they pass**

Expected: All 5 tests PASS

**Step 5: Commit**

```bash
git add Liney/Services/Tmux/TmuxService.swift Tests/TmuxServiceTests.swift
git commit -m "feat: add tmux service for session listing and attach commands"
```

---

## Task 4: SFTP Service

**Files:**
- Create: `Liney/Services/SFTP/SFTPDirectoryEntry.swift`
- Create: `Liney/Services/SFTP/SFTPService.swift`
- Test: `Tests/SFTPServiceTests.swift`

**Note:** This task requires the Citadel library. Before starting, add Citadel as a dependency. Check whether the project uses SPM or a vendored approach. If SPM, add to Package.swift. If Xcode project, add via Xcode's package dependencies (File → Add Package → `https://github.com/orlandos-nl/Citadel`). If Citadel integration is not immediately possible, implement just the system SSH path first and mark the Citadel fallback as TODO.

**Step 1: Write the test file and SFTPDirectoryEntry model**

```swift
// Liney/Services/SFTP/SFTPDirectoryEntry.swift
import Foundation

struct SFTPDirectoryEntry: Hashable, Comparable {
    let name: String
    let path: String

    static func < (lhs: SFTPDirectoryEntry, rhs: SFTPDirectoryEntry) -> Bool {
        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
```

```swift
// Tests/SFTPServiceTests.swift
import XCTest
@testable import Liney

final class SFTPServiceTests: XCTestCase {

    func testSFTPDirectoryEntrySorting() {
        let entries = [
            SFTPDirectoryEntry(name: "zebra", path: "/zebra"),
            SFTPDirectoryEntry(name: "alpha", path: "/alpha"),
            SFTPDirectoryEntry(name: "beta", path: "/beta"),
        ]
        let sorted = entries.sorted()
        XCTAssertEqual(sorted.map(\.name), ["alpha", "beta", "zebra"])
    }

    func testSFTPServiceErrorDescriptions() {
        let errors: [SFTPServiceError] = [
            .notConnected,
            .authenticationFailed,
            .keyFileNotFound("/path"),
            .commandFailed("reason"),
        ]
        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }
}
```

**Step 2: Run tests to verify they fail**

Expected: Compilation error — `SFTPServiceError` not defined

**Step 3: Write the SFTP service**

```swift
// Liney/Services/SFTP/SFTPService.swift
import Foundation

enum SFTPServiceError: LocalizedError {
    case notConnected
    case authenticationFailed
    case keyFileNotFound(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to remote server"
        case .authenticationFailed:
            return "SSH authentication failed"
        case .keyFileNotFound(let path):
            return "SSH key file not found: \(path)"
        case .commandFailed(let reason):
            return "SSH command failed: \(reason)"
        }
    }
}

/// Manages SFTP connections for remote directory browsing.
actor SFTPService {

    private enum ConnectionMode {
        case none
        case ssh(SSHSessionConfiguration)
        // case citadel(client, sftp) — add when Citadel is integrated
    }

    private var mode: ConnectionMode = .none

    // MARK: - Connection (System SSH, key-based)

    func connect(target: SSHSessionConfiguration) async throws {
        let result = try await runSSH(target: target, command: "echo __OK__")
        guard result.exitCode == 0, result.stdout.contains("__OK__") else {
            throw SFTPServiceError.authenticationFailed
        }
        mode = .ssh(target)
    }

    // MARK: - Connection (Citadel password fallback)
    // TODO: Implement when Citadel dependency is added
    // func connectWithPassword(target: SSHSessionConfiguration, password: String) async throws

    // MARK: - Directory Operations

    func listDirectories(at path: String) async throws -> [SFTPDirectoryEntry] {
        guard case .ssh(let target) = mode else {
            throw SFTPServiceError.notConnected
        }
        let result = try await runSSH(target: target, command: "ls -1pa \(path.shellQuoted)")
        guard result.exitCode == 0 else {
            throw SFTPServiceError.commandFailed(result.stderr)
        }
        return result.stdout
            .components(separatedBy: .newlines)
            .filter { $0.hasSuffix("/") && $0 != "./" && $0 != "../" && !$0.hasPrefix(".") }
            .map { name in
                let cleanName = String(name.dropLast()) // remove trailing "/"
                let fullPath = path == "/" ? "/\(cleanName)" : "\(path)/\(cleanName)"
                return SFTPDirectoryEntry(name: cleanName, path: fullPath)
            }
            .sorted()
    }

    func homeDirectory() async throws -> String {
        guard case .ssh(let target) = mode else {
            throw SFTPServiceError.notConnected
        }
        let result = try await runSSH(target: target, command: "echo $HOME")
        guard result.exitCode == 0 else {
            throw SFTPServiceError.commandFailed(result.stderr)
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func disconnect() {
        mode = .none
    }

    // MARK: - SSH Execution

    private func runSSH(target: SSHSessionConfiguration, command: String) async throws -> ShellCommandResult {
        var args = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
            "-o", "StrictHostKeyChecking=accept-new",
        ]
        if let port = target.port {
            args.append(contentsOf: ["-p", String(port)])
        }
        if let identityFilePath = target.identityFilePath, !identityFilePath.isEmpty {
            let expanded = (identityFilePath as NSString).expandingTildeInPath
            args.append(contentsOf: ["-i", expanded])
        }
        args.append(target.destination)
        args.append(command)
        return try await ShellCommandRunner.run("/usr/bin/ssh", arguments: args, timeout: 15)
    }
}
```

**Step 4: Run tests to verify they pass**

Expected: All tests PASS

**Step 5: Commit**

```bash
git add Liney/Services/SFTP/SFTPDirectoryEntry.swift Liney/Services/SFTP/SFTPService.swift Tests/SFTPServiceTests.swift
git commit -m "feat: add SFTP service for remote directory browsing"
```

---

## Task 5: Data Model Extensions — SessionBackendConfiguration + TmuxAttach

**Files:**
- Modify: `Liney/Domain/WorkspaceModels.swift:98-104` (SessionBackendKind)
- Modify: `Liney/Domain/WorkspaceModels.swift:629-690` (SessionBackendConfiguration)
- Modify: `Liney/Services/Terminal/SessionBackendLaunch.swift:35-104` (makeLaunchConfiguration)
- Test: `Tests/SessionBackendTmuxTests.swift`

**Step 1: Write the test file**

```swift
// Tests/SessionBackendTmuxTests.swift
import XCTest
@testable import Liney

final class SessionBackendTmuxTests: XCTestCase {

    func testTmuxAttachConfigurationCodable() throws {
        let config = TmuxAttachConfiguration(
            sessionName: "dev",
            windowIndex: 2,
            isRemote: true,
            sshConfig: SSHSessionConfiguration(
                host: "example.com", user: "admin", port: 22,
                identityFilePath: nil, remoteWorkingDirectory: nil, remoteCommand: nil
            )
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(TmuxAttachConfiguration.self, from: data)
        XCTAssertEqual(decoded.sessionName, "dev")
        XCTAssertEqual(decoded.windowIndex, 2)
        XCTAssertTrue(decoded.isRemote)
        XCTAssertEqual(decoded.sshConfig?.host, "example.com")
    }

    func testSessionBackendConfigurationTmuxAttachFactory() {
        let config = TmuxAttachConfiguration(
            sessionName: "work", windowIndex: nil, isRemote: false, sshConfig: nil
        )
        let backend = SessionBackendConfiguration.tmuxAttach(config)
        XCTAssertEqual(backend.kind, .tmuxAttach)
        XCTAssertEqual(backend.tmuxAttach?.sessionName, "work")
    }

    func testSessionBackendConfigurationTmuxAttachCodable() throws {
        let tmux = TmuxAttachConfiguration(
            sessionName: "test", windowIndex: nil, isRemote: false, sshConfig: nil
        )
        let backend = SessionBackendConfiguration.tmuxAttach(tmux)
        let data = try JSONEncoder().encode(backend)
        let decoded = try JSONDecoder().decode(SessionBackendConfiguration.self, from: data)
        XCTAssertEqual(decoded.kind, .tmuxAttach)
        XCTAssertEqual(decoded.tmuxAttach?.sessionName, "test")
    }

    func testSessionBackendConfigurationTmuxDisplayName() {
        let tmux = TmuxAttachConfiguration(
            sessionName: "myproject", windowIndex: nil, isRemote: false, sshConfig: nil
        )
        let backend = SessionBackendConfiguration.tmuxAttach(tmux)
        XCTAssertTrue(backend.displayName.contains("myproject"))
    }

    func testBackwardCompatibility_OldDataWithoutTmux() throws {
        // Simulate old JSON without tmuxAttach field
        let json = """
        {"kind": "localShell", "localShell": {"shellPath": "/bin/zsh", "shellArguments": ["-l"]}}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SessionBackendConfiguration.self, from: data)
        XCTAssertEqual(decoded.kind, .localShell)
        XCTAssertNil(decoded.tmuxAttach)
    }
}
```

**Step 2: Run tests to verify they fail**

Expected: Compilation error — `TmuxAttachConfiguration` not defined

**Step 3: Add TmuxAttachConfiguration struct and extend SessionBackendConfiguration**

In `Liney/Domain/WorkspaceModels.swift`:

3a. Add `.tmuxAttach` case to `SessionBackendKind` (after line 101):
```swift
case tmuxAttach
```
With display name in the switch (after line 110):
```swift
case .tmuxAttach:
    return lineyLocalizedModelString("session.backend.tmuxAttach")
```

3b. Add `TmuxAttachConfiguration` struct (after `AgentSessionConfiguration`, around line 174):
```swift
struct TmuxAttachConfiguration: Codable, Hashable {
    var sessionName: String
    var windowIndex: Int?
    var isRemote: Bool
    var sshConfig: SSHSessionConfiguration?
}
```

3c. Add `tmuxAttach` property and factory to `SessionBackendConfiguration` (around line 633):
- Add property: `var tmuxAttach: TmuxAttachConfiguration?`
- Add factory method:
```swift
static func tmuxAttach(_ configuration: TmuxAttachConfiguration) -> SessionBackendConfiguration {
    SessionBackendConfiguration(
        kind: .tmuxAttach,
        localShell: nil,
        ssh: nil,
        agent: nil,
        tmuxAttach: configuration
    )
}
```
- Update `displayName`:
```swift
case .tmuxAttach:
    return "tmux: \(tmuxAttach?.sessionName ?? kind.displayName)"
```

3d. Update `SessionBackendConfiguration` init to accept tmuxAttach parameter with default nil.

3e. In `SessionBackendLaunch.swift`, add the `.tmuxAttach` case to `makeLaunchConfiguration` (after the `.agent` case, before the closing `}`):
```swift
case .tmuxAttach:
    let config = tmuxAttach ?? TmuxAttachConfiguration(
        sessionName: "default", windowIndex: nil, isRemote: false, sshConfig: nil
    )

    var arguments: [String] = []
    let executablePath: String

    if config.isRemote, let sshConfig = config.sshConfig {
        executablePath = "/usr/bin/ssh"
        var sshArgs: [String] = ["-t"]
        if let port = sshConfig.port {
            sshArgs.append(contentsOf: ["-p", String(port)])
        }
        if let identityFile = sshConfig.identityFilePath, !identityFile.isEmpty {
            sshArgs.append(contentsOf: ["-i", identityFile])
        }
        sshArgs.append(sshConfig.destination)
        var tmuxCmd = "tmux attach-session -t \(config.sessionName.shellQuoted)"
        if let windowIndex = config.windowIndex {
            tmuxCmd = "tmux attach-session -t \(config.sessionName.shellQuoted):\(windowIndex)"
        }
        sshArgs.append(tmuxCmd)
        arguments = sshArgs
    } else {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        executablePath = shell
        var tmuxCmd = "exec tmux attach-session -t \(config.sessionName.shellQuoted)"
        if let windowIndex = config.windowIndex {
            tmuxCmd = "exec tmux attach-session -t \(config.sessionName.shellQuoted):\(windowIndex)"
        }
        arguments = ["--login", "-c", tmuxCmd]
    }

    return TerminalLaunchConfiguration(
        workingDirectory: NSHomeDirectory(),
        environment: baseEnvironment,
        command: TerminalCommandDefinition(
            executablePath: executablePath,
            arguments: arguments,
            displayName: "tmux: \(config.sessionName)"
        ),
        backendConfiguration: self,
        initialInput: nil
    )
```

3f. Add localization entry for tmuxAttach display name in `L10n.swift`:
- English: `"session.backend.tmuxAttach": "tmux"`
- Chinese: `"session.backend.tmuxAttach": "tmux"`

**Step 4: Run tests to verify they pass**

Expected: All 5 tests PASS

**Step 5: Commit**

```bash
git add Liney/Domain/WorkspaceModels.swift Liney/Services/Terminal/SessionBackendLaunch.swift Liney/Support/L10n.swift Tests/SessionBackendTmuxTests.swift
git commit -m "feat: add tmuxAttach backend type with launch configuration"
```

---

## Task 6: Data Model Extensions — PaneSnapshot + WorkspaceRecord + WorkspaceModel

**Files:**
- Modify: `Liney/Domain/WorkspaceModels.swift:76-88` (WorkspaceKind)
- Modify: `Liney/Domain/WorkspaceModels.swift:912-974` (PaneSnapshot)
- Modify: `Liney/Domain/WorkspaceModels.swift:1272-1366` (WorkspaceRecord)
- Modify: `Liney/Domain/WorkspaceRuntime.swift:12-80` (WorkspaceModel)
- Test: `Tests/RemoteWorkspaceModelTests.swift`

**Step 1: Write the test file**

```swift
// Tests/RemoteWorkspaceModelTests.swift
import XCTest
@testable import Liney

final class RemoteWorkspaceModelTests: XCTestCase {

    func testWorkspaceKindRemoteServer() {
        let kind = WorkspaceKind.remoteServer
        XCTAssertEqual(kind.rawValue, "remoteServer")
        XCTAssertFalse(kind.displayName.isEmpty)
    }

    func testPaneSnapshotWithDetectedTmuxSession() throws {
        let snapshot = PaneSnapshot(
            id: UUID(),
            preferredWorkingDirectory: "/tmp",
            preferredEngine: .libghosttyPreferred,
            backendConfiguration: .local(),
            detectedTmuxSession: "myproject"
        )
        XCTAssertEqual(snapshot.detectedTmuxSession, "myproject")

        // Codable round-trip
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(PaneSnapshot.self, from: data)
        XCTAssertEqual(decoded.detectedTmuxSession, "myproject")
    }

    func testPaneSnapshotBackwardCompatibility_NoTmux() throws {
        // Old JSON without detectedTmuxSession
        let json = """
        {
            "id": "550E8400-E29B-41D4-A716-446655440000",
            "preferredWorkingDirectory": "/tmp",
            "preferredEngine": "libghosttyPreferred",
            "backendConfiguration": {"kind": "localShell", "localShell": {"shellPath": "/bin/zsh", "shellArguments": ["-l"]}}
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PaneSnapshot.self, from: data)
        XCTAssertNil(decoded.detectedTmuxSession)
    }

    func testWorkspaceRecordWithSSHTarget() throws {
        let sshConfig = SSHSessionConfiguration(
            host: "prod.example.com", user: "deploy", port: 22,
            identityFilePath: nil, remoteWorkingDirectory: "/srv/app", remoteCommand: nil
        )
        let record = WorkspaceRecord(
            id: UUID(),
            kind: .remoteServer,
            name: "Production",
            repositoryRoot: "/srv/app",
            activeWorktreePath: "/srv/app",
            worktreeStates: [],
            isSidebarExpanded: false,
            sshTarget: sshConfig
        )
        XCTAssertEqual(record.sshTarget?.host, "prod.example.com")

        // Codable round-trip
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(WorkspaceRecord.self, from: data)
        XCTAssertEqual(decoded.kind, .remoteServer)
        XCTAssertEqual(decoded.sshTarget?.host, "prod.example.com")
    }

    func testWorkspaceRecordBackwardCompatibility_NoSSHTarget() throws {
        let json = """
        {
            "id": "550E8400-E29B-41D4-A716-446655440000",
            "name": "local-project",
            "repositoryRoot": "/Users/test/project",
            "activeWorktreePath": "/Users/test/project",
            "worktreeStates": [],
            "isSidebarExpanded": false
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WorkspaceRecord.self, from: data)
        XCTAssertNil(decoded.sshTarget)
        XCTAssertEqual(decoded.kind, .repository)
    }
}
```

**Step 2: Run tests to verify they fail**

Expected: Compilation error — `WorkspaceKind.remoteServer` doesn't exist

**Step 3: Extend the data models**

3a. Add `.remoteServer` to `WorkspaceKind` in `WorkspaceModels.swift:78`:
```swift
case remoteServer
```
With display name:
```swift
case .remoteServer:
    return lineyLocalizedModelString("workspace.kind.remoteServer")
```

3b. Add `detectedTmuxSession` to `PaneSnapshot`. Update the struct, CodingKeys, init, and custom Codable:
- Add property: `var detectedTmuxSession: String?`
- Add CodingKey: `case detectedTmuxSession`
- Update init to accept `detectedTmuxSession: String? = nil`
- Update `init(from decoder:)`: `detectedTmuxSession = try container.decodeIfPresent(String.self, forKey: .detectedTmuxSession)`
- Update `encode(to:)`: `try container.encodeIfPresent(detectedTmuxSession, forKey: .detectedTmuxSession)`

3c. Add `sshTarget` to `WorkspaceRecord`:
- Add property: `var sshTarget: SSHSessionConfiguration?`
- Add CodingKey: `case sshTarget`
- Update init to accept `sshTarget: SSHSessionConfiguration? = nil`
- Update `init(from decoder:)`: `sshTarget = try container.decodeIfPresent(SSHSessionConfiguration.self, forKey: .sshTarget)`
- Update `encode(to:)`: `try container.encodeIfPresent(sshTarget, forKey: .sshTarget)`

3d. Add `sshTarget` and `isRemote` to `WorkspaceModel` in `WorkspaceRuntime.swift`:
- Add: `@Published var sshTarget: SSHSessionConfiguration?`
- Add: `var isRemote: Bool { sshTarget != nil }`
- In init: `self.sshTarget = record.sshTarget`

3e. Add localization entries in `L10n.swift`:
- English: `"workspace.kind.remoteServer": "Remote"`
- Chinese: `"workspace.kind.remoteServer": "远程"`

**Step 4: Run tests to verify they pass**

Expected: All tests PASS

**Step 5: Commit**

```bash
git add Liney/Domain/WorkspaceModels.swift Liney/Domain/WorkspaceRuntime.swift Liney/Support/L10n.swift Tests/RemoteWorkspaceModelTests.swift
git commit -m "feat: add remoteServer workspace kind, PaneSnapshot tmux field, WorkspaceRecord sshTarget"
```

---

## Task 7: ShellSession — Tmux Detection

**Files:**
- Modify: `Liney/Services/Terminal/ShellSession.swift:73-151` (add tmux detection)
- Create: `Liney/Services/Process/ProcessTree.swift`
- Test: `Tests/TmuxDetectionTests.swift`

**Step 1: Write the test file**

```swift
// Tests/TmuxDetectionTests.swift
import XCTest
@testable import Liney

final class TmuxDetectionTests: XCTestCase {

    // Test the static parsing methods (no ShellSession instance needed)

    func testDetectTmuxStatusBarFormat() {
        let result = TmuxTitleDetector.detectSession(fromTitle: "[myproject] 0:bash")
        XCTAssertEqual(result, "myproject")
    }

    func testDetectTmuxStatusBarFormatMultipleWindows() {
        let result = TmuxTitleDetector.detectSession(fromTitle: "[dev] 1:vim  2:bash")
        XCTAssertEqual(result, "dev")
    }

    func testDetectTmuxPreexecNewSession() {
        let result = TmuxTitleDetector.detectSession(fromTitle: "tmux new -s hello")
        XCTAssertEqual(result, "hello")
    }

    func testDetectTmuxPreexecAttach() {
        let result = TmuxTitleDetector.detectSession(fromTitle: "tmux attach -t mysession")
        XCTAssertEqual(result, "mysession")
    }

    func testDetectTmuxPreexecAttachWithWindowTarget() {
        let result = TmuxTitleDetector.detectSession(fromTitle: "tmux attach -t work:2")
        XCTAssertEqual(result, "work")
    }

    func testDetectTmuxBareTmuxCommand() {
        let result = TmuxTitleDetector.detectSession(fromTitle: "tmux")
        XCTAssertEqual(result, "tmux") // placeholder, resolved async later
    }

    func testDetectTmuxSetTitlesFormat() {
        let result = TmuxTitleDetector.detectSession(fromTitle: "dev:0:bash - \"hostname\"")
        XCTAssertEqual(result, "dev")
    }

    func testDetectTmuxSetTitlesFormatNumberedSession() {
        let result = TmuxTitleDetector.detectSession(fromTitle: "13:0:bash - \"hostname\"")
        XCTAssertEqual(result, "13")
    }

    func testNoTmuxDetectedForNormalTitle() {
        let result = TmuxTitleDetector.detectSession(fromTitle: "vim /etc/hosts")
        XCTAssertNil(result)
    }

    func testNoTmuxDetectedForEmptyTitle() {
        let result = TmuxTitleDetector.detectSession(fromTitle: "")
        XCTAssertNil(result)
    }

    func testParseTmuxSessionNameFromArgs() {
        XCTAssertEqual(TmuxTitleDetector.parseTmuxSessionName(from: ["new", "-s", "hello"]), "hello")
        XCTAssertEqual(TmuxTitleDetector.parseTmuxSessionName(from: ["attach", "-t", "work"]), "work")
        XCTAssertEqual(TmuxTitleDetector.parseTmuxSessionName(from: ["a", "-t", "session:2"]), "session")
        XCTAssertNil(TmuxTitleDetector.parseTmuxSessionName(from: []))
        XCTAssertNil(TmuxTitleDetector.parseTmuxSessionName(from: ["ls"]))
    }

    func testProcessTreeParseTmuxClientList() {
        let output = "12345 main\n67890 dev\n"
        let clients = ProcessTree.parseTmuxClientList(output)
        XCTAssertEqual(clients.count, 2)
        XCTAssertEqual(clients[0].clientPID, 12345)
        XCTAssertEqual(clients[0].sessionName, "main")
        XCTAssertEqual(clients[1].clientPID, 67890)
        XCTAssertEqual(clients[1].sessionName, "dev")
    }
}
```

**Step 2: Run tests to verify they fail**

Expected: Compilation error — `TmuxTitleDetector`, `ProcessTree` not defined

**Step 3: Create TmuxTitleDetector and ProcessTree**

3a. Create `TmuxTitleDetector` as a utility enum (can be in ShellSession.swift or its own file):

```swift
// Add to Liney/Services/Terminal/ShellSession.swift (or create Liney/Services/Tmux/TmuxTitleDetector.swift)

/// Detects tmux sessions from terminal title changes.
enum TmuxTitleDetector {

    /// Returns detected tmux session name, or nil if no tmux detected.
    static func detectSession(fromTitle title: String) -> String? {
        let lower = title.lowercased()

        // Pattern 1: tmux status bar format "[session-name] ..."
        if lower.hasPrefix("[") {
            if let closeBracket = title.firstIndex(of: "]") {
                let sessionName = String(title[title.index(after: title.startIndex)..<closeBracket])
                if !sessionName.isEmpty {
                    return sessionName
                }
            }
        }

        // Pattern 2: preexec title showing tmux command
        if lower.hasPrefix("tmux") {
            let args = title.split(separator: " ").map(String.init)
            if args.first?.lowercased() == "tmux" {
                if let sessionName = parseTmuxSessionName(from: Array(args.dropFirst())) {
                    return sessionName
                }
                return "tmux" // bare tmux — resolve async later
            }
        }

        // Pattern 3: tmux set-titles format "#S:#I:#W - \"#T\""
        let parts = title.split(separator: ":", maxSplits: 2).map(String.init)
        if parts.count == 3,
           let _ = Int(parts[1]),
           parts[2].contains(" - ") {
            let sessionName = parts[0]
            if !sessionName.isEmpty {
                return sessionName
            }
        }

        return nil
    }

    /// Parses session name from tmux subcommand arguments.
    static func parseTmuxSessionName(from args: [String]) -> String? {
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg == "-s", i + 1 < args.count {
                return args[i + 1]
            }
            if arg == "-t", i + 1 < args.count {
                let target = args[i + 1]
                if let colonIdx = target.firstIndex(of: ":") {
                    return String(target[target.startIndex..<colonIdx])
                }
                return target
            }
            i += 1
        }
        return nil
    }
}
```

3b. Create `ProcessTree` for process hierarchy walking:

```swift
// Liney/Services/Process/ProcessTree.swift
import Foundation
import Darwin

/// Utilities for walking the process tree (used for tmux client discovery).
enum ProcessTree {

    struct ProcessEntry {
        let pid: pid_t
        let parentPID: pid_t
        let command: String
    }

    /// Returns all running processes via sysctl.
    static func allProcesses() -> [ProcessEntry] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size: Int = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0 else { return [] }
        let count = size / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        guard sysctl(&mib, UInt32(mib.count), &procs, &size, nil, 0) == 0 else { return [] }
        let actualCount = size / MemoryLayout<kinfo_proc>.stride
        return (0..<actualCount).map { i in
            let p = procs[i]
            let pid = p.kp_proc.p_pid
            let ppid = p.kp_eproc.e_ppid
            let name = withUnsafePointer(to: p.kp_proc.p_comm) { ptr in
                String(cString: UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self))
            }
            return ProcessEntry(pid: pid, parentPID: ppid, command: name)
        }
    }

    /// BFS to find all descendant PIDs of a given process.
    static func descendants(of pid: pid_t) -> Set<pid_t> {
        let all = allProcesses()
        var childrenMap: [pid_t: [pid_t]] = [:]
        for p in all {
            childrenMap[p.parentPID, default: []].append(p.pid)
        }
        var result = Set<pid_t>()
        var queue = childrenMap[pid] ?? []
        while let next = queue.first {
            queue.removeFirst()
            guard result.insert(next).inserted else { continue }
            queue.append(contentsOf: childrenMap[next] ?? [])
        }
        return result
    }

    /// Parses `tmux list-clients -F '#{client_pid} #{session_name}'` output.
    static func parseTmuxClientList(_ output: String) -> [(clientPID: pid_t, sessionName: String)] {
        output.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2, let pid = pid_t(parts[0]) else { return nil }
            return (clientPID: pid, sessionName: parts[1])
        }
    }
}
```

3c. Add `detectedTmuxSession` property and tmux detection to `ShellSession`:

In `ShellSession.swift`, add published property:
```swift
@Published var detectedTmuxSession: String?
```

Modify `configureSurfaceCallbacks` to call tmux detection on title change:
```swift
surfaceController.onTitleChange = { [weak self] title in
    guard let self, !title.isEmpty else { return }
    self.title = title
    self.detectTmux(fromTitle: title)
}
```

Add private method:
```swift
private func detectTmux(fromTitle title: String) {
    guard let sessionName = TmuxTitleDetector.detectSession(fromTitle: title) else {
        return
    }

    if sessionName == "tmux" {
        // Bare tmux — resolve exact session via process tree
        detectedTmuxSession = "tmux"
        resolveExactTmuxSession()
    } else {
        detectedTmuxSession = sessionName
    }
}

private func resolveExactTmuxSession() {
    Task { [weak self] in
        var shellPID: pid_t?
        for _ in 0..<15 {
            try? await Task.sleep(nanoseconds: 200_000_000)
            shellPID = await MainActor.run { self?.pid }
            if shellPID != nil { break }
        }
        guard let shellPID else { return }

        var sessionName: String?
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 300_000_000)
            let desc = ProcessTree.descendants(of: shellPID)
            if desc.isEmpty { continue }

            let result = await Self.queryTmuxClients()
            guard let result else { continue }

            let clients = ProcessTree.parseTmuxClientList(result)
            if let match = clients.first(where: { desc.contains($0.clientPID) }) {
                sessionName = match.sessionName
                break
            }
        }

        guard let sessionName else { return }
        await MainActor.run { [weak self] in
            guard let self, self.detectedTmuxSession == "tmux" else { return }
            self.detectedTmuxSession = sessionName
        }
    }
}

private nonisolated static func queryTmuxClients() async -> String? {
    let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    do {
        let result = try await ShellCommandRunner.run(
            shell, arguments: ["-lc", "tmux list-clients -F '#{client_pid} #{session_name}'"]
        )
        return result.exitCode == 0 ? result.stdout : nil
    } catch {
        return nil
    }
}
```

**Step 4: Run tests to verify they pass**

Expected: All tests PASS

**Step 5: Commit**

```bash
git add Liney/Services/Terminal/ShellSession.swift Liney/Services/Process/ProcessTree.swift Tests/TmuxDetectionTests.swift
git commit -m "feat: add tmux session detection from terminal title changes"
```

---

## Task 8: WorkspaceSessionController — Tmux Restore Logic

**Files:**
- Modify: `Liney/Services/Terminal/WorkspaceSessionController.swift:44-55` (replaceSessions)
- Test: `Tests/TmuxRestoreTests.swift`

**Step 1: Write the test file**

```swift
// Tests/TmuxRestoreTests.swift
import XCTest
@testable import Liney

final class TmuxRestoreTests: XCTestCase {

    func testTmuxRestoreReplacesLocalShellWithTmuxAttach() {
        let paneID = UUID()
        let snapshot = PaneSnapshot(
            id: paneID,
            preferredWorkingDirectory: "/tmp",
            preferredEngine: .libghosttyPreferred,
            backendConfiguration: .local(),
            detectedTmuxSession: "myproject"
        )

        let restored = WorkspaceSessionController.applyTmuxRestore(to: snapshot)
        XCTAssertEqual(restored.backendConfiguration.kind, .tmuxAttach)
        XCTAssertEqual(restored.backendConfiguration.tmuxAttach?.sessionName, "myproject")
        XCTAssertFalse(restored.backendConfiguration.tmuxAttach?.isRemote ?? true)
    }

    func testTmuxRestoreReplacesSSHWithRemoteTmuxAttach() {
        let paneID = UUID()
        let sshConfig = SSHSessionConfiguration(
            host: "example.com", user: "admin", port: 22,
            identityFilePath: nil, remoteWorkingDirectory: nil, remoteCommand: nil
        )
        let snapshot = PaneSnapshot(
            id: paneID,
            preferredWorkingDirectory: "/tmp",
            preferredEngine: .libghosttyPreferred,
            backendConfiguration: .ssh(sshConfig),
            detectedTmuxSession: "remotedev"
        )

        let restored = WorkspaceSessionController.applyTmuxRestore(to: snapshot)
        XCTAssertEqual(restored.backendConfiguration.kind, .tmuxAttach)
        XCTAssertEqual(restored.backendConfiguration.tmuxAttach?.sessionName, "remotedev")
        XCTAssertTrue(restored.backendConfiguration.tmuxAttach?.isRemote ?? false)
        XCTAssertEqual(restored.backendConfiguration.tmuxAttach?.sshConfig?.host, "example.com")
    }

    func testTmuxRestoreDoesNothingWithoutTmuxSession() {
        let paneID = UUID()
        let snapshot = PaneSnapshot(
            id: paneID,
            preferredWorkingDirectory: "/tmp",
            preferredEngine: .libghosttyPreferred,
            backendConfiguration: .local(),
            detectedTmuxSession: nil
        )

        let restored = WorkspaceSessionController.applyTmuxRestore(to: snapshot)
        XCTAssertEqual(restored.backendConfiguration.kind, .localShell)
    }

    func testTmuxRestoreDoesNothingForAgentBackend() {
        let paneID = UUID()
        let agentConfig = AgentSessionConfiguration(
            name: "Claude", launchPath: "/usr/bin/env",
            arguments: ["claude"], environment: [:], workingDirectory: nil
        )
        let snapshot = PaneSnapshot(
            id: paneID,
            preferredWorkingDirectory: "/tmp",
            preferredEngine: .libghosttyPreferred,
            backendConfiguration: .agent(agentConfig),
            detectedTmuxSession: "somesession"
        )

        let restored = WorkspaceSessionController.applyTmuxRestore(to: snapshot)
        XCTAssertEqual(restored.backendConfiguration.kind, .agent)
    }
}
```

**Step 2: Run tests to verify they fail**

Expected: Compilation error — `applyTmuxRestore` not defined

**Step 3: Add tmux restore logic to WorkspaceSessionController**

Add a static method (so it's testable without @MainActor issues) and integrate into `replaceSessions`:

```swift
// In WorkspaceSessionController.swift

/// Applies tmux restore: if the snapshot has a detected tmux session, replace the backend
/// with a tmuxAttach configuration so the session is automatically reattached on restore.
static func applyTmuxRestore(to snapshot: PaneSnapshot) -> PaneSnapshot {
    guard let tmuxSession = snapshot.detectedTmuxSession else { return snapshot }

    var restored = snapshot
    switch snapshot.backendConfiguration.kind {
    case .localShell:
        restored.backendConfiguration = .tmuxAttach(TmuxAttachConfiguration(
            sessionName: tmuxSession,
            windowIndex: nil,
            isRemote: false,
            sshConfig: nil
        ))
    case .ssh:
        restored.backendConfiguration = .tmuxAttach(TmuxAttachConfiguration(
            sessionName: tmuxSession,
            windowIndex: nil,
            isRemote: true,
            sshConfig: snapshot.backendConfiguration.ssh
        ))
    default:
        break
    }
    return restored
}
```

Then modify `replaceSessions` to apply tmux restore before creating sessions:

```swift
func replaceSessions(with paneSnapshots: [PaneSnapshot], focusedPaneID: UUID?, defaultWorkingDirectory: String) {
    sessions.values.forEach { $0.terminate() }
    sessions.removeAll()

    let preparedSnapshots = paneSnapshots.isEmpty ? [PaneSnapshot.makeDefault(cwd: defaultWorkingDirectory)] : paneSnapshots
    for snapshot in preparedSnapshots {
        let restored = Self.applyTmuxRestore(to: snapshot)
        sessions[restored.id] = ShellSession(snapshot: restored)
    }
    // ... rest unchanged
}
```

**Step 4: Run tests to verify they pass**

Expected: All 4 tests PASS

**Step 5: Commit**

```bash
git add Liney/Services/Terminal/WorkspaceSessionController.swift Tests/TmuxRestoreTests.swift
git commit -m "feat: auto-restore tmux sessions on workspace reopen"
```

---

## Task 9: Enhanced SSH Launch — tmux set-titles injection

**Files:**
- Modify: `Liney/Services/Terminal/SessionBackendLaunch.swift:169-180` (sshBootstrapCommands)

**Step 1: Write a test**

```swift
// Add to Tests/SessionBackendTmuxTests.swift

func testSSHBootstrapInjectsTmuxSetTitles() {
    let sshConfig = SSHSessionConfiguration(
        host: "example.com", user: "admin", port: nil,
        identityFilePath: nil, remoteWorkingDirectory: nil, remoteCommand: nil
    )
    let backend = SessionBackendConfiguration.ssh(sshConfig)
    let launch = backend.makeLaunchConfiguration(
        preferredWorkingDirectory: "/tmp",
        baseEnvironment: [:]
    )
    // The initialInput should contain tmux set-titles
    XCTAssertTrue(launch.initialInput?.contains("tmux set-option") ?? false,
                  "SSH bootstrap should inject tmux set-titles on")
}
```

**Step 2: Run test to verify it fails**

Expected: FAIL — current bootstrap commands don't include tmux set-titles

**Step 3: Add tmux set-titles injection**

In `SessionBackendLaunch.swift`, in the `sshBootstrapCommands()` method, add at the beginning of the commands array:

```swift
func sshBootstrapCommands() -> [String] {
    var commands = [
        // Enable tmux set-titles so session name propagates to terminal title
        #"tmux set-option -g set-titles on 2>/dev/null; true"#,
        #"if [ -n "$ZSH_VERSION" ]; then bindkey $'\e[1;3D' backward-word 2>/dev/null; ..."#,
        // ... existing keybinding commands unchanged ...
    ]
    // ... rest unchanged
}
```

**Step 4: Run tests to verify they pass**

Expected: All tests PASS

**Step 5: Commit**

```bash
git add Liney/Services/Terminal/SessionBackendLaunch.swift Tests/SessionBackendTmuxTests.swift
git commit -m "feat: inject tmux set-titles on SSH sessions for title detection"
```

---

## Task 10: Remote Git Inspection

**Files:**
- Modify: `Liney/Services/Git/GitRepositoryService.swift` (add remote inspection)
- Test: `Tests/RemoteGitInspectionTests.swift`

**Step 1: Write the test file**

```swift
// Tests/RemoteGitInspectionTests.swift
import XCTest
@testable import Liney

final class RemoteGitInspectionTests: XCTestCase {

    func testParseRemoteGitInspectionOutput() {
        let output = """
        __BRANCH__
        main
        __HEAD__
        abc1234
        __STATUS__
        M  file1.txt
        ?? file2.txt
        __AHEAD_BEHIND__
        2\t1
        """
        let result = GitRepositoryService.parseRemoteInspection(output)
        XCTAssertEqual(result.branch, "main")
        XCTAssertEqual(result.head, "abc1234")
        XCTAssertEqual(result.changedFileCount, 2)
        XCTAssertEqual(result.aheadCount, 2)
        XCTAssertEqual(result.behindCount, 1)
    }

    func testParseRemoteGitInspectionEmptyStatus() {
        let output = """
        __BRANCH__
        develop
        __HEAD__
        def5678
        __STATUS__
        __AHEAD_BEHIND__
        0\t0
        """
        let result = GitRepositoryService.parseRemoteInspection(output)
        XCTAssertEqual(result.branch, "develop")
        XCTAssertEqual(result.changedFileCount, 0)
        XCTAssertEqual(result.aheadCount, 0)
    }

    func testParseRemoteGitInspectionNoUpstream() {
        let output = """
        __BRANCH__
        feature
        __HEAD__
        aaa1111
        __STATUS__
        __AHEAD_BEHIND__
        """
        let result = GitRepositoryService.parseRemoteInspection(output)
        XCTAssertEqual(result.branch, "feature")
        XCTAssertEqual(result.aheadCount, 0)
        XCTAssertEqual(result.behindCount, 0)
    }
}
```

**Step 2: Run tests to verify they fail**

Expected: Compilation error — `parseRemoteInspection` not defined

**Step 3: Add remote git inspection**

Add to `GitRepositoryService`:

```swift
/// Result of a remote git inspection.
struct RemoteGitSnapshot {
    var branch: String
    var head: String
    var changedFileCount: Int
    var aheadCount: Int
    var behindCount: Int
}

/// Parses the output of the combined remote git inspection script.
static func parseRemoteInspection(_ output: String) -> RemoteGitSnapshot {
    var branch = ""
    var head = ""
    var changedFileCount = 0
    var aheadCount = 0
    var behindCount = 0

    var currentSection = ""
    for line in output.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("__") && trimmed.hasSuffix("__") {
            currentSection = trimmed
            continue
        }
        guard !trimmed.isEmpty else { continue }

        switch currentSection {
        case "__BRANCH__":
            branch = trimmed
        case "__HEAD__":
            head = trimmed
        case "__STATUS__":
            changedFileCount += 1
        case "__AHEAD_BEHIND__":
            let parts = trimmed.components(separatedBy: "\t")
            if parts.count == 2 {
                aheadCount = Int(parts[0]) ?? 0
                behindCount = Int(parts[1]) ?? 0
            }
        default:
            break
        }
    }

    return RemoteGitSnapshot(
        branch: branch, head: head,
        changedFileCount: changedFileCount,
        aheadCount: aheadCount, behindCount: behindCount
    )
}

/// Inspects a remote git repository via SSH.
func inspectRemoteRepository(remotePath: String, sshConfig: SSHSessionConfiguration) async throws -> RemoteGitSnapshot {
    let escapedPath = remotePath.shellQuoted
    let script = """
    cd \(escapedPath) && \
    echo __BRANCH__ && git rev-parse --abbrev-ref HEAD 2>/dev/null && \
    echo __HEAD__ && git rev-parse --short HEAD 2>/dev/null && \
    echo __STATUS__ && git status --porcelain 2>/dev/null && \
    echo __AHEAD_BEHIND__ && git rev-list --left-right --count HEAD...@{upstream} 2>/dev/null || true
    """
    var args = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10"]
    if let port = sshConfig.port {
        args.append(contentsOf: ["-p", String(port)])
    }
    if let identityFile = sshConfig.identityFilePath, !identityFile.isEmpty {
        args.append(contentsOf: ["-i", (identityFile as NSString).expandingTildeInPath])
    }
    args.append(sshConfig.destination)
    args.append(script)

    let result = try await ShellCommandRunner.run("/usr/bin/ssh", arguments: args, timeout: 15)
    return Self.parseRemoteInspection(result.stdout)
}
```

**Step 4: Run tests to verify they pass**

Expected: All 3 tests PASS

**Step 5: Commit**

```bash
git add Liney/Services/Git/GitRepositoryService.swift Tests/RemoteGitInspectionTests.swift
git commit -m "feat: add remote git repository inspection via SSH"
```

---

## Task 11: Periodic Remote Refresh

**Files:**
- Modify: `Liney/App/WorkspaceStore.swift` (add remote refresh scheduler)

**Step 1: Add the refresh scheduler**

Add to `WorkspaceStore`:

```swift
// MARK: - Remote Workspace Refresh

/// How often to poll SSH-backed workspaces for git state changes.
/// File system events cannot reach across SSH, so we fall back to periodic polling.
private static let remoteRefreshInterval: TimeInterval = 30

private var remoteRefreshTimer: Timer?
private var remoteWindowObserver: NSObjectProtocol?
private var isRefreshingRemotes = false

func startRemoteWorkspaceRefreshScheduler() {
    let timer = Timer(timeInterval: Self.remoteRefreshInterval, repeats: true) { [weak self] _ in
        Task { @MainActor [weak self] in
            await self?.refreshAllRemoteWorkspaces()
        }
    }
    timer.tolerance = 5
    RunLoop.main.add(timer, forMode: .common)
    remoteRefreshTimer = timer

    remoteWindowObserver = NotificationCenter.default.addObserver(
        forName: NSWindow.didBecomeKeyNotification,
        object: nil,
        queue: .main
    ) { [weak self] _ in
        Task { @MainActor [weak self] in
            await self?.refreshAllRemoteWorkspaces()
        }
    }
}

func stopRemoteWorkspaceRefreshScheduler() {
    remoteRefreshTimer?.invalidate()
    remoteRefreshTimer = nil
    if let observer = remoteWindowObserver {
        NotificationCenter.default.removeObserver(observer)
    }
    remoteWindowObserver = nil
}

private func refreshAllRemoteWorkspaces() async {
    guard !isRefreshingRemotes else { return }
    let remotes = workspaces.filter { $0.isRemote && !$0.isArchived }
    guard !remotes.isEmpty else { return }
    isRefreshingRemotes = true
    defer { isRefreshingRemotes = false }
    for workspace in remotes {
        await refreshRemoteWorkspace(workspace)
    }
}

private func refreshRemoteWorkspace(_ workspace: WorkspaceModel) async {
    guard let sshConfig = workspace.sshTarget else { return }
    let remotePath = workspace.activeWorktreePath
    do {
        let snapshot = try await gitService.inspectRemoteRepository(
            remotePath: remotePath, sshConfig: sshConfig
        )
        workspace.currentBranch = snapshot.branch
        workspace.head = snapshot.head
        workspace.hasUncommittedChanges = snapshot.changedFileCount > 0
        workspace.changedFileCount = snapshot.changedFileCount
        workspace.aheadCount = snapshot.aheadCount
        workspace.behindCount = snapshot.behindCount
    } catch {
        if AppLogger.isEnabled {
            AppLogger.workspace.error("Remote refresh failed for \(workspace.name): \(error.localizedDescription)")
        }
    }
}
```

Then call `startRemoteWorkspaceRefreshScheduler()` from the existing initialization path (where `WorkspaceStore` sets up its services after loading state).

**Step 2: Verify manually**

This is integration code that requires running SSH — verify by adding a remote workspace and observing that git state updates periodically.

**Step 3: Commit**

```bash
git add Liney/App/WorkspaceStore.swift
git commit -m "feat: add periodic remote workspace git state refresh"
```

---

## Task 12: Remote Workspace Creation — WorkspaceStore Integration

**Files:**
- Modify: `Liney/App/WorkspaceStore.swift` (add addRemoteWorkspace, createRemoteWorkspaceRequest)
- Modify: `Liney/Domain/WorkspaceModels.swift` (add CreateRemoteWorkspaceRequest)

**Step 1: Add the request model**

In `WorkspaceModels.swift`, add:

```swift
struct CreateRemoteWorkspaceRequest: Identifiable {
    let id = UUID()
}
```

**Step 2: Add to WorkspaceStore**

```swift
// Add published property
@Published var createRemoteWorkspaceRequest: CreateRemoteWorkspaceRequest?

// Add presentation method
func presentCreateRemoteWorkspace() {
    createRemoteWorkspaceRequest = CreateRemoteWorkspaceRequest()
}

// Add workspace creation method
func addRemoteWorkspace(sshConfig: SSHSessionConfiguration, name: String) {
    let record = WorkspaceRecord(
        id: UUID(),
        kind: .remoteServer,
        name: name,
        repositoryRoot: sshConfig.remoteWorkingDirectory ?? "/",
        activeWorktreePath: sshConfig.remoteWorkingDirectory ?? "/",
        worktreeStates: [],
        isSidebarExpanded: false,
        sshTarget: sshConfig
    )
    let model = WorkspaceModel(record: record)
    workspaces.append(model)
    selectedWorkspaceID = model.id
    persist()

    Task {
        await refreshRemoteWorkspace(model)
    }
}
```

**Step 3: Add command palette entry**

In the `allCommandPaletteItems` builder, add a new global command:

```swift
CommandPaletteItem(
    id: "global.createRemoteWorkspace",
    title: localized("palette.createRemoteWorkspace"),
    subtitle: nil,
    group: localized("palette.group.global"),
    keywords: ["remote", "ssh", "server"],
    kind: .createRemoteWorkspace
)
```

Add `.createRemoteWorkspace` case to the command palette action enum and handle it:
```swift
case .createRemoteWorkspace:
    dismissCommandPalette()
    presentCreateRemoteWorkspace()
```

Add localization:
- English: `"palette.createRemoteWorkspace": "New Remote Workspace"`
- Chinese: `"palette.createRemoteWorkspace": "新建远程工作区"`

**Step 4: Commit**

```bash
git add Liney/Domain/WorkspaceModels.swift Liney/App/WorkspaceStore.swift Liney/Support/L10n.swift
git commit -m "feat: add remote workspace creation to WorkspaceStore and command palette"
```

---

## Task 13: RemoteDirectoryBrowser UI

**Files:**
- Create: `Liney/UI/Sheets/RemoteDirectoryBrowserViewModel.swift`
- Create: `Liney/UI/Sheets/RemoteDirectoryBrowser.swift`

**Step 1: Create the ViewModel**

```swift
// Liney/UI/Sheets/RemoteDirectoryBrowserViewModel.swift
import Foundation

@MainActor
final class DirectoryNode: ObservableObject, Identifiable {
    let id = UUID()
    let name: String
    let path: String
    @Published var children: [DirectoryNode] = []
    @Published var isExpanded = false
    @Published var isLoading = false
    @Published var error: String?

    init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

@MainActor
final class RemoteDirectoryBrowserViewModel: ObservableObject {

    enum ConnectionState {
        case idle
        case connecting
        case connected
        case passwordRequired
        case error(String)
    }

    let sshConfig: SSHSessionConfiguration

    @Published var connectionState: ConnectionState = .idle
    @Published var rootNodes: [DirectoryNode] = []
    @Published var currentPath: String = ""
    @Published var selectedPath: String = ""
    @Published var password: String = ""

    private let sftpService = SFTPService()

    init(sshConfig: SSHSessionConfiguration) {
        self.sshConfig = sshConfig
    }

    func connect() async {
        connectionState = .connecting
        do {
            try await sftpService.connect(target: sshConfig)
            connectionState = .connected
            await loadHomeDirectory()
        } catch let error as SFTPServiceError where error == .authenticationFailed {
            connectionState = .passwordRequired
        } catch {
            connectionState = .error(error.localizedDescription)
        }
    }

    func connectWithPassword() async {
        connectionState = .connecting
        // TODO: Implement Citadel password connection
        // For now, show error
        connectionState = .error("Password authentication not yet supported. Please configure SSH key auth.")
    }

    func loadHomeDirectory() async {
        do {
            let home = try await sftpService.homeDirectory()
            currentPath = home
            selectedPath = home
            await loadDirectory(at: home)
        } catch {
            connectionState = .error(error.localizedDescription)
        }
    }

    func loadDirectory(at path: String) async {
        do {
            let entries = try await sftpService.listDirectories(at: path)
            rootNodes = entries.map { DirectoryNode(name: $0.name, path: $0.path) }
            currentPath = path
            selectedPath = path
        } catch {
            connectionState = .error(error.localizedDescription)
        }
    }

    func expandNode(_ node: DirectoryNode) async {
        guard !node.isExpanded else { return }
        node.isLoading = true
        do {
            let entries = try await sftpService.listDirectories(at: node.path)
            node.children = entries.map { DirectoryNode(name: $0.name, path: $0.path) }
            node.isExpanded = true
        } catch {
            node.error = error.localizedDescription
        }
        node.isLoading = false
    }

    func navigateTo(path: String) async {
        let normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        await loadDirectory(at: normalized)
    }

    func disconnect() async {
        await sftpService.disconnect()
        connectionState = .idle
    }
}

// Make SFTPServiceError conform to Equatable for pattern matching
extension SFTPServiceError: Equatable {
    static func == (lhs: SFTPServiceError, rhs: SFTPServiceError) -> Bool {
        switch (lhs, rhs) {
        case (.notConnected, .notConnected): return true
        case (.authenticationFailed, .authenticationFailed): return true
        case (.keyFileNotFound(let a), .keyFileNotFound(let b)): return a == b
        case (.commandFailed(let a), .commandFailed(let b)): return a == b
        default: return false
        }
    }
}
```

**Step 2: Create the SwiftUI view**

```swift
// Liney/UI/Sheets/RemoteDirectoryBrowser.swift
import SwiftUI

struct RemoteDirectoryBrowser: View {
    @StateObject private var viewModel: RemoteDirectoryBrowserViewModel
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var localization = LocalizationManager.shared

    init(sshConfig: SSHSessionConfiguration, onSelect: @escaping (String) -> Void) {
        _viewModel = StateObject(wrappedValue: RemoteDirectoryBrowserViewModel(sshConfig: sshConfig))
        self.onSelect = onSelect
    }

    private func localized(_ key: String) -> String {
        localization.string(key)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title
            HStack {
                Text(localized("remote.browser.title"))
                    .font(.headline)
                Spacer()
                Text(viewModel.sshConfig.destination)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            // Path bar
            HStack {
                TextField(localized("remote.browser.path"), text: $viewModel.currentPath)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await viewModel.navigateTo(path: viewModel.currentPath) }
                    }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Content
            Group {
                switch viewModel.connectionState {
                case .idle, .connecting:
                    VStack {
                        ProgressView()
                        Text(localized("remote.browser.connecting"))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .connected:
                    if viewModel.rootNodes.isEmpty {
                        Text(localized("remote.browser.empty"))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(viewModel.rootNodes) { node in
                                DirectoryNodeRow(node: node, viewModel: viewModel) {
                                    viewModel.selectedPath = node.path
                                }
                            }
                        }
                        .listStyle(.plain)
                    }

                case .passwordRequired:
                    VStack(spacing: 12) {
                        Text(localized("remote.browser.passwordRequired"))
                        SecureField(localized("remote.browser.password"), text: $viewModel.password)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 250)
                        Button(localized("remote.browser.connect")) {
                            Task { await viewModel.connectWithPassword() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .error(let message):
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundStyle(.red)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            Divider()

            // Bottom bar
            HStack {
                if !viewModel.selectedPath.isEmpty {
                    Text(viewModel.selectedPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button(localized("common.cancel")) { dismiss() }
                Button(localized("remote.browser.open")) {
                    onSelect(viewModel.selectedPath)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.selectedPath.isEmpty)
            }
            .padding()
        }
        .frame(width: 480, height: 420)
        .task {
            await viewModel.connect()
        }
    }
}

private struct DirectoryNodeRow: View {
    @ObservedObject var node: DirectoryNode
    let viewModel: RemoteDirectoryBrowserViewModel
    let onSelect: () -> Void

    var body: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { node.isExpanded },
            set: { expanded in
                if expanded {
                    Task { await viewModel.expandNode(node) }
                } else {
                    node.isExpanded = false
                }
            }
        )) {
            if node.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.leading, 8)
            } else if let error = node.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                ForEach(node.children) { child in
                    DirectoryNodeRow(node: child, viewModel: viewModel) {
                        viewModel.selectedPath = child.path
                    }
                }
            }
        } label: {
            HStack {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(node.name)
            }
            .contentShape(Rectangle())
            .onTapGesture { onSelect() }
        }
    }
}
```

Add localization entries in `L10n.swift`:
- English:
  ```
  "remote.browser.title": "Browse Remote Directory"
  "remote.browser.path": "Path"
  "remote.browser.connecting": "Connecting..."
  "remote.browser.empty": "No directories found"
  "remote.browser.passwordRequired": "Key authentication failed. Enter password:"
  "remote.browser.password": "Password"
  "remote.browser.connect": "Connect"
  "remote.browser.open": "Open"
  ```
- Chinese:
  ```
  "remote.browser.title": "浏览远程目录"
  "remote.browser.path": "路径"
  "remote.browser.connecting": "连接中..."
  "remote.browser.empty": "未找到目录"
  "remote.browser.passwordRequired": "密钥认证失败，请输入密码："
  "remote.browser.password": "密码"
  "remote.browser.connect": "连接"
  "remote.browser.open": "打开"
  ```

**Step 3: Commit**

```bash
git add Liney/UI/Sheets/RemoteDirectoryBrowserViewModel.swift Liney/UI/Sheets/RemoteDirectoryBrowser.swift Liney/Support/L10n.swift
git commit -m "feat: add remote directory browser UI with SFTP backend"
```

---

## Task 14: CreateRemoteWorkspaceSheet

**Files:**
- Create: `Liney/UI/Sheets/CreateRemoteWorkspaceSheet.swift`
- Modify: `Liney/UI/MainWindowView.swift:565` (add sheet presentation)

**Step 1: Create the sheet**

```swift
// Liney/UI/Sheets/CreateRemoteWorkspaceSheet.swift
import SwiftUI

struct CreateRemoteWorkspaceSheet: View {
    let onCreate: (SSHSessionConfiguration, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var localization = LocalizationManager.shared

    @State private var sshEntries: [SSHConfigEntry] = []
    @State private var selectedEntryIndex: Int?
    @State private var host = ""
    @State private var user = ""
    @State private var port = "22"
    @State private var identityFile = ""
    @State private var remotePath = ""
    @State private var workspaceName = ""
    @State private var connectionStatus: SSHConnectionStatus?
    @State private var isTesting = false
    @State private var showDirectoryBrowser = false

    private func localized(_ key: String) -> String {
        localization.string(key)
    }

    private var sshConfig: SSHSessionConfiguration {
        SSHSessionConfiguration(
            host: host,
            user: user.isEmpty ? nil : user,
            port: Int(port),
            identityFilePath: identityFile.isEmpty ? nil : identityFile,
            remoteWorkingDirectory: remotePath.isEmpty ? nil : remotePath,
            remoteCommand: nil
        )
    }

    private var canCreate: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty &&
        !workspaceName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func applyEntry(_ entry: SSHConfigEntry) {
        host = entry.host
        user = entry.user ?? ""
        port = String(entry.port)
        identityFile = entry.identityFile ?? ""
        connectionStatus = nil
    }

    private func testConnection() {
        isTesting = true
        connectionStatus = nil
        let entry = SSHConfigEntry(
            displayName: workspaceName,
            host: host,
            port: Int(port) ?? 22,
            user: user.isEmpty ? nil : user,
            identityFile: identityFile.isEmpty ? nil : identityFile
        )
        Task {
            let service = SSHConfigService()
            let status = await service.testConnection(entry)
            isTesting = false
            connectionStatus = status
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localized("sheet.remote.title"))
                .font(.system(size: 18, weight: .semibold))

            Text(localized("sheet.remote.description"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            // SSH Config entries
            if !sshEntries.isEmpty {
                GroupBox(localized("sheet.remote.sshConfig")) {
                    Picker(localized("sheet.remote.sshConfig"), selection: $selectedEntryIndex) {
                        Text(localized("sheet.remote.manual")).tag(Int?.none)
                        ForEach(Array(sshEntries.enumerated()), id: \.offset) { index, entry in
                            Text("\(entry.displayName) (\(entry.host))").tag(Optional(index))
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedEntryIndex) { _, newValue in
                        if let index = newValue {
                            applyEntry(sshEntries[index])
                        }
                    }
                    .padding(.top, 8)
                }
            }

            // Connection details
            GroupBox(localized("sheet.remote.connection")) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField(localized("sheet.ssh.host"), text: $host)
                    TextField(localized("sheet.ssh.user"), text: $user)
                    TextField(localized("sheet.ssh.port"), text: $port)
                    TextField(localized("sheet.ssh.identityFile"), text: $identityFile)

                    HStack {
                        TextField(localized("sheet.ssh.remoteWorkingDirectory"), text: $remotePath)
                        Button(localized("sheet.remote.browse")) {
                            showDirectoryBrowser = true
                        }
                        .disabled(host.isEmpty)
                    }

                    // Connection test
                    HStack {
                        Button(localized("sheet.remote.testConnection")) {
                            testConnection()
                        }
                        .disabled(host.isEmpty || isTesting)

                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        }

                        if let status = connectionStatus {
                            switch status {
                            case .connected:
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            case .authRequired:
                                Image(systemName: "key.fill")
                                    .foregroundStyle(.yellow)
                            case .unreachable:
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
                .textFieldStyle(.roundedBorder)
                .padding(.top, 8)
            }

            // Workspace name
            GroupBox(localized("sheet.remote.name")) {
                TextField(localized("sheet.remote.namePlaceholder"), text: $workspaceName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.top, 8)
            }

            // Actions
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Label(localized("common.cancel"), systemImage: "xmark")
                }
                Button {
                    onCreate(sshConfig, workspaceName)
                    dismiss()
                } label: {
                    Label(localized("sheet.remote.create"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canCreate)
            }
        }
        .padding(20)
        .frame(width: 520)
        .task {
            let service = SSHConfigService()
            sshEntries = await service.loadSSHConfig()
        }
        .sheet(isPresented: $showDirectoryBrowser) {
            RemoteDirectoryBrowser(sshConfig: sshConfig) { path in
                remotePath = path
                if workspaceName.isEmpty {
                    workspaceName = (path as NSString).lastPathComponent
                }
            }
        }
    }
}
```

Add localization entries in `L10n.swift`:
- English:
  ```
  "sheet.remote.title": "New Remote Workspace"
  "sheet.remote.description": "Connect to a remote server via SSH."
  "sheet.remote.sshConfig": "SSH Config"
  "sheet.remote.manual": "Manual"
  "sheet.remote.connection": "Connection"
  "sheet.remote.browse": "Browse..."
  "sheet.remote.testConnection": "Test Connection"
  "sheet.remote.name": "Workspace Name"
  "sheet.remote.namePlaceholder": "Enter workspace name"
  "sheet.remote.create": "Create"
  ```
- Chinese:
  ```
  "sheet.remote.title": "新建远程工作区"
  "sheet.remote.description": "通过 SSH 连接到远程服务器。"
  "sheet.remote.sshConfig": "SSH 配置"
  "sheet.remote.manual": "手动输入"
  "sheet.remote.connection": "连接"
  "sheet.remote.browse": "浏览..."
  "sheet.remote.testConnection": "测试连接"
  "sheet.remote.name": "工作区名称"
  "sheet.remote.namePlaceholder": "输入工作区名称"
  "sheet.remote.create": "创建"
  ```

**Step 2: Wire up the sheet in MainWindowView**

In `MainWindowView.swift`, after the existing `.sheet(item: $store.createAgentSessionRequest)` block, add:

```swift
.sheet(item: $store.createRemoteWorkspaceRequest) { _ in
    CreateRemoteWorkspaceSheet { sshConfig, name in
        store.addRemoteWorkspace(sshConfig: sshConfig, name: name)
    }
}
```

**Step 3: Commit**

```bash
git add Liney/UI/Sheets/CreateRemoteWorkspaceSheet.swift Liney/UI/MainWindowView.swift Liney/Support/L10n.swift
git commit -m "feat: add CreateRemoteWorkspaceSheet with SSH config picker and directory browser"
```

---

## Task 15: Sidebar Remote Badge

**Files:**
- Modify: `Liney/UI/Sidebar/WorkspaceSidebarView.swift:1815-1831` (WorkspaceRowContent badges)
- Modify: `Liney/Support/L10n.swift` (add badge entry)

**Step 1: Add the badge**

In `WorkspaceSidebarView.swift`, in the `WorkspaceRowContent` HStack where badges are displayed (around line 1811), add before or after the existing session count badge:

```swift
if workspace.isRemote {
    SidebarInfoBadge(text: localized("sidebar.badge.remote"), tone: .accent)
}
```

**Step 2: Add localization entries**

In `L10n.swift`:
- English: `"sidebar.badge.remote": "remote"`
- Chinese: `"sidebar.badge.remote": "远程"`

**Step 3: Commit**

```bash
git add Liney/UI/Sidebar/WorkspaceSidebarView.swift Liney/Support/L10n.swift
git commit -m "feat: add remote workspace badge in sidebar"
```

---

## Task 16: Sidebar Entry Points

**Files:**
- Modify: `Liney/UI/Sidebar/WorkspaceSidebarView.swift` (add menu item)
- Modify: `Liney/Support/ApplicationMenuController.swift` (add File menu item)

**Step 1: Add sidebar context menu / toolbar entry**

Find where "Add Workspace" or similar actions are in the sidebar toolbar/bottom area. Add a new entry:

```swift
// In the sidebar toolbar or bottom "+" menu
Button {
    store?.presentCreateRemoteWorkspace()
} label: {
    Label(localized("sidebar.action.addRemoteWorkspace"), systemImage: "network")
}
```

**Step 2: Add File menu entry**

In `ApplicationMenuController.swift`, in the File menu builder, add:

```swift
let addRemoteItem = NSMenuItem(
    title: localized("menu.file.newRemoteWorkspace"),
    action: #selector(addRemoteWorkspace),
    keyEquivalent: ""
)
```

With the action handler calling `store.presentCreateRemoteWorkspace()`.

**Step 3: Add localization**

- English:
  ```
  "sidebar.action.addRemoteWorkspace": "Add Remote Workspace"
  "menu.file.newRemoteWorkspace": "New Remote Workspace..."
  ```
- Chinese:
  ```
  "sidebar.action.addRemoteWorkspace": "添加远程工作区"
  "menu.file.newRemoteWorkspace": "新建远程工作区..."
  ```

**Step 4: Commit**

```bash
git add Liney/UI/Sidebar/WorkspaceSidebarView.swift Liney/Support/ApplicationMenuController.swift Liney/Support/L10n.swift
git commit -m "feat: add remote workspace entry points in sidebar and File menu"
```

---

## Task 17: Integration Testing and Cleanup

**Step 1: Run the full test suite**

```bash
xcodebuild test -project Liney.xcodeproj -scheme Liney 2>&1 | tail -30
```

Fix any failures.

**Step 2: Manual integration test**

1. Launch Liney
2. Use Command Palette → "New Remote Workspace" to verify the sheet appears
3. Verify `~/.ssh/config` entries load in the picker
4. Test connection to a real SSH server
5. Browse remote directories
6. Create a remote workspace and verify it appears in sidebar with "remote" badge
7. Verify git state (branch, ahead/behind) populates after 30s or window focus
8. Open a terminal in the remote workspace, start tmux
9. Quit and relaunch Liney — verify tmux session auto-reattaches
10. Verify the "remote"/"远程" badge shows in both languages

**Step 3: Final commit**

```bash
git add -A
git commit -m "chore: integration fixes for remote server support"
```
