//
//  ShellSessionTests.swift
//  LineyTests
//
//  Author: everettjf
//

import AppKit
import XCTest
@testable import Liney

final class ShellSessionTests: XCTestCase {
    func testGhosttyShellIntegrationInjectsZshEnvironmentFromBundledResources() {
        let resourcesRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let ghosttyResources = resourcesRoot.appendingPathComponent("ghostty", isDirectory: true)
        let zshIntegration = ghosttyResources.appendingPathComponent("shell-integration/zsh", isDirectory: true)
        let terminfo = resourcesRoot.appendingPathComponent("terminfo", isDirectory: true)

        try? FileManager.default.createDirectory(at: zshIntegration, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: terminfo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: resourcesRoot) }

        let prepared = LineyGhosttyShellIntegration.prepare(
            command: TerminalCommandDefinition(
                executablePath: "/bin/zsh",
                arguments: ["-l"],
                displayName: "zsh"
            ),
            environment: ["ZDOTDIR": "/tmp/original-zdotdir"],
            resourcePaths: LineyGhosttyResourcePaths(resourceRootURL: resourcesRoot)
        )

        XCTAssertEqual(prepared.command.executablePath, "/bin/zsh")
        XCTAssertEqual(prepared.command.arguments, ["-l"])
        XCTAssertEqual(prepared.environment["TERM"], "xterm-ghostty")
        XCTAssertEqual(prepared.environment["TERMINFO"], terminfo.path)
        XCTAssertEqual(prepared.environment["GHOSTTY_RESOURCES_DIR"], ghosttyResources.path)
        XCTAssertEqual(prepared.environment["GHOSTTY_SHELL_FEATURES"], "ssh-env")
        XCTAssertEqual(prepared.environment["GHOSTTY_ZSH_ZDOTDIR"], "/tmp/original-zdotdir")
        XCTAssertEqual(prepared.environment["ZDOTDIR"], zshIntegration.path)
    }

    func testGhosttyShellIntegrationInjectsFishEnvironmentFromBundledResources() {
        let resourcesRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let ghosttyResources = resourcesRoot.appendingPathComponent("ghostty", isDirectory: true)
        let fishVendorDirectory = ghosttyResources.appendingPathComponent("shell-integration/fish/vendor_conf.d", isDirectory: true)
        let terminfo = resourcesRoot.appendingPathComponent("terminfo", isDirectory: true)

        try? FileManager.default.createDirectory(at: fishVendorDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: terminfo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: resourcesRoot) }

        let prepared = LineyGhosttyShellIntegration.prepare(
            command: TerminalCommandDefinition(
                executablePath: "/opt/homebrew/bin/fish",
                arguments: ["-l"],
                displayName: "fish"
            ),
            environment: ["XDG_DATA_DIRS": "/usr/local/share:/usr/share"],
            resourcePaths: LineyGhosttyResourcePaths(resourceRootURL: resourcesRoot)
        )

        XCTAssertEqual(prepared.environment["TERM"], "xterm-ghostty")
        XCTAssertEqual(prepared.environment["TERMINFO"], terminfo.path)
        XCTAssertEqual(prepared.environment["GHOSTTY_RESOURCES_DIR"], ghosttyResources.path)
        XCTAssertEqual(prepared.environment["GHOSTTY_SHELL_FEATURES"], "ssh-env")
        XCTAssertEqual(
            prepared.environment["GHOSTTY_SHELL_INTEGRATION_XDG_DIR"],
            ghosttyResources.appendingPathComponent("shell-integration", isDirectory: true).path
        )
        XCTAssertEqual(
            prepared.environment["XDG_DATA_DIRS"],
            [
                ghosttyResources.appendingPathComponent("shell-integration", isDirectory: true).path,
                "/usr/local/share",
                "/usr/share",
            ].joined(separator: ":")
        )
    }

    func testGhosttyShellIntegrationPreservesExistingShellFeaturesWhileAppendingSSHEnv() {
        let prepared = LineyGhosttyShellIntegration.prepare(
            command: TerminalCommandDefinition(
                executablePath: "/bin/zsh",
                arguments: ["-l"],
                displayName: "zsh"
            ),
            environment: [
                "GHOSTTY_SHELL_FEATURES": "cursor,title",
            ],
            resourcePaths: LineyGhosttyResourcePaths(
                ghosttyResourcesDirectory: "/tmp/ghostty",
                terminfoDirectory: "/tmp/terminfo"
            )
        )

        XCTAssertEqual(prepared.environment["GHOSTTY_SHELL_FEATURES"], "cursor,title,ssh-env")
    }

    func testGhosttyBootstrapPublishesBundledResourcesDirectory() {
        let environment = LineyGhosttyBootstrap.processEnvironment(
            resourcePaths: LineyGhosttyResourcePaths(
                ghosttyResourcesDirectory: "/tmp/liney-ghostty",
                terminfoDirectory: "/tmp/liney-terminfo"
            )
        )

        XCTAssertEqual(environment["GHOSTTY_RESOURCES_DIR"], "/tmp/liney-ghostty")
    }

    func testLocalShellDefaultUsesResolvedLoginShellPath() {
        let configuration = LocalShellSessionConfiguration.fromLoginShellPath("/opt/homebrew/bin/fish")

        XCTAssertEqual(configuration.shellPath, "/opt/homebrew/bin/fish")
        XCTAssertEqual(configuration.shellArguments, ["-l"])
    }

    func testLocalShellDefaultFallsBackToLegacyZshWhenLoginShellIsUnavailable() {
        let configuration = LocalShellSessionConfiguration.fromLoginShellPath(nil)

        XCTAssertEqual(configuration, .legacyDefault)
    }

    func testAugmentedExecutablePathPrependsCommonUserAndHomebrewDirectories() {
        XCTAssertEqual(
            lineyAugmentedExecutablePath("/usr/bin:/bin", homeDirectory: "/Users/tester"),
            [
                "/Users/tester/.local/bin",
                "/Users/tester/.cargo/bin",
                "/Users/tester/.bun/bin",
                "/Users/tester/.deno/bin",
                "/opt/homebrew/bin",
                "/opt/homebrew/sbin",
                "/usr/local/bin",
                "/usr/local/sbin",
                "/usr/bin",
                "/bin",
                "/usr/sbin",
                "/sbin",
            ].joined(separator: ":")
        )
    }

    func testLocalShellBackendResolvesLegacyDefaultToCurrentLoginShell() {
        let backend = SessionBackendConfiguration.local(
            shellPath: LocalShellSessionConfiguration.legacyDefault.shellPath,
            shellArguments: LocalShellSessionConfiguration.legacyDefault.shellArguments
        )
        let resolved = backend.resolvedLocalShellConfiguration(
            defaultConfiguration: LocalShellSessionConfiguration.fromLoginShellPath("/opt/homebrew/bin/fish")
        )

        XCTAssertEqual(resolved.shellPath, "/opt/homebrew/bin/fish")
        XCTAssertEqual(resolved.shellArguments, ["-l"])
    }

    func testExplicitNonDefaultLocalShellConfigurationIsPreserved() {
        let backend = SessionBackendConfiguration.local(
            shellPath: "/bin/bash",
            shellArguments: ["-lc", "echo hi"]
        )
        let resolved = backend.resolvedLocalShellConfiguration(
            defaultConfiguration: LocalShellSessionConfiguration.fromLoginShellPath("/opt/homebrew/bin/fish")
        )

        XCTAssertEqual(resolved.shellPath, "/bin/bash")
        XCTAssertEqual(resolved.shellArguments, ["-lc", "echo hi"])
    }

    func testSSHBackendForcesRemoteTTYForInteractiveSessions() {
        let configuration = SessionBackendConfiguration.ssh(
            SSHSessionConfiguration(
                host: "example.com",
                user: "dev",
                port: 2222,
                identityFilePath: "~/.ssh/id_ed25519",
                remoteWorkingDirectory: "/srv/app",
                remoteCommand: nil
            )
        )

        let launchConfiguration = configuration.makeLaunchConfiguration(
            preferredWorkingDirectory: "/tmp/liney-ssh",
            baseEnvironment: [:]
        )

        XCTAssertEqual(launchConfiguration.command.executablePath, "/usr/bin/ssh")
        XCTAssertEqual(
            launchConfiguration.command.arguments,
            [
                "-tt",
                "-o", "SetEnv COLORTERM=truecolor",
                "-o", "SendEnv TERM_PROGRAM TERM_PROGRAM_VERSION",
                "-p", "2222",
                "-i", "~/.ssh/id_ed25519",
                "dev@example.com",
            ]
        )
        XCTAssertEqual(launchConfiguration.initialInput, "cd '/srv/app'\n")
    }

    func testSSHBackendPreservesExplicitRemoteCommandInvocation() {
        let configuration = SessionBackendConfiguration.ssh(
            SSHSessionConfiguration(
                host: "example.com",
                user: "dev",
                port: nil,
                identityFilePath: nil,
                remoteWorkingDirectory: "/srv/app",
                remoteCommand: "tmux attach || tmux"
            )
        )

        let launchConfiguration = configuration.makeLaunchConfiguration(
            preferredWorkingDirectory: "/tmp/liney-ssh",
            baseEnvironment: [:]
        )

        XCTAssertEqual(
            launchConfiguration.command.arguments,
            [
                "-tt",
                "-o", "SetEnv COLORTERM=truecolor",
                "-o", "SendEnv TERM_PROGRAM TERM_PROGRAM_VERSION",
                "dev@example.com",
                "cd '/srv/app' && tmux attach || tmux",
            ]
        )
        XCTAssertNil(launchConfiguration.initialInput)
    }

    func testStartIfNeededOnlyAutoStartsIdleSession() async {
        await MainActor.run {
            let surface = FakeManagedTerminalSurfaceController()
            let session = ShellSession(
                snapshot: PaneSnapshot.makeDefault(cwd: "/tmp/liney-shell-session"),
                surfaceController: surface
            )

            XCTAssertEqual(session.lifecycle, .idle)
            XCTAssertFalse(session.hasActiveProcess)
            XCTAssertFalse(session.isRunning)

            session.startIfNeeded()

            XCTAssertEqual(surface.startCallCount, 1)
            XCTAssertEqual(session.lifecycle, .running)
            XCTAssertTrue(session.hasActiveProcess)
            XCTAssertFalse(session.isRunning)
            XCTAssertEqual(session.pid, surface.managedPID)

            surface.needsConfirmQuit = true
            XCTAssertTrue(session.isRunning)

            surface.emitProcessExit(7)

            XCTAssertEqual(session.lifecycle, .exited)
            XCTAssertFalse(session.hasActiveProcess)
            XCTAssertFalse(session.isRunning)
            XCTAssertEqual(session.exitCode, 7)
            XCTAssertNil(session.pid)

            session.startIfNeeded()

            XCTAssertEqual(surface.startCallCount, 1)
            XCTAssertEqual(session.lifecycle, .exited)
        }
    }

    func testRestartTransitionsExitedSessionBackToRunning() async {
        await MainActor.run {
            let surface = FakeManagedTerminalSurfaceController()
            let session = ShellSession(
                snapshot: PaneSnapshot.makeDefault(cwd: "/tmp/liney-shell-session-restart"),
                surfaceController: surface
            )

            session.startIfNeeded()
            surface.emitProcessExit(1)

            session.restart()

            XCTAssertEqual(surface.restartCallCount, 1)
            XCTAssertEqual(session.lifecycle, .running)
            XCTAssertTrue(session.hasActiveProcess)
            XCTAssertNil(session.exitCode)
            XCTAssertEqual(session.pid, surface.managedPID)
        }
    }

    func testIsRunningTracksForegroundCommandStateInsteadOfShellLifetime() async {
        await MainActor.run {
            let surface = FakeManagedTerminalSurfaceController()
            let session = ShellSession(
                snapshot: PaneSnapshot.makeDefault(cwd: "/tmp/liney-shell-session-command-state"),
                surfaceController: surface
            )

            session.startIfNeeded()

            XCTAssertTrue(session.hasActiveProcess)
            XCTAssertFalse(session.isRunning)

            surface.needsConfirmQuit = true
            XCTAssertTrue(session.isRunning)

            surface.needsConfirmQuit = false
            XCTAssertFalse(session.isRunning)
            XCTAssertTrue(session.hasActiveProcess)
        }
    }

    func testRestartReapsPreviousLaunchConfiguration() async {
        await MainActor.run {
            let surface = FakeManagedTerminalSurfaceController()
            var reapedConfigurations: [TerminalLaunchConfiguration] = []
            let session = ShellSession(
                snapshot: PaneSnapshot.makeDefault(cwd: "/tmp/liney-shell-session-reap-restart"),
                surfaceController: surface,
                processReaper: { reapedConfigurations.append($0) }
            )

            let initialLaunchPath = session.launchPath
            let initialLaunchArguments = session.launchArguments

            session.startIfNeeded()
            session.restart()

            XCTAssertEqual(reapedConfigurations.count, 1)
            XCTAssertEqual(reapedConfigurations[0].command.executablePath, initialLaunchPath)
            XCTAssertEqual(reapedConfigurations[0].command.arguments, initialLaunchArguments)
            XCTAssertEqual(surface.restartCallCount, 1)
        }
    }

    func testTerminateReapsCurrentLaunchConfiguration() async {
        await MainActor.run {
            let surface = FakeManagedTerminalSurfaceController()
            var reapedConfigurations: [TerminalLaunchConfiguration] = []
            let session = ShellSession(
                snapshot: PaneSnapshot.makeDefault(cwd: "/tmp/liney-shell-session-reap-terminate"),
                surfaceController: surface,
                processReaper: { reapedConfigurations.append($0) }
            )

            session.startIfNeeded()
            let runningLaunchPath = session.launchPath
            let runningLaunchArguments = session.launchArguments

            session.terminate()

            XCTAssertEqual(reapedConfigurations.count, 1)
            XCTAssertEqual(reapedConfigurations[0].command.executablePath, runningLaunchPath)
            XCTAssertEqual(reapedConfigurations[0].command.arguments, runningLaunchArguments)
            XCTAssertEqual(surface.terminateCallCount, 1)
        }
    }

    func testSendShellCommandUsesCarriageReturnSubmission() async {
        await MainActor.run {
            let surface = FakeManagedTerminalSurfaceController()
            let session = ShellSession(
                snapshot: PaneSnapshot.makeDefault(cwd: "/tmp/liney-shell-session-send-command"),
                surfaceController: surface
            )

            session.sendShellCommand("codex")

            XCTAssertEqual(surface.sentTexts, ["codex"])
            XCTAssertEqual(surface.sendReturnCallCount, 1)
        }
    }

    func testInsertTextDoesNotAppendReturn() async {
        await MainActor.run {
            let surface = FakeManagedTerminalSurfaceController()
            let session = ShellSession(
                snapshot: PaneSnapshot.makeDefault(cwd: "/tmp/liney-shell-session-insert-text"),
                surfaceController: surface
            )

            session.insertText("codex")

            XCTAssertEqual(surface.sentTexts, ["codex"])
        }
    }

    func testSnapshotPromotesLocalTmuxSessionToRestorableLaunch() async {
        await MainActor.run {
            let surface = FakeManagedTerminalSurfaceController()
            let session = ShellSession(
                snapshot: PaneSnapshot.makeDefault(cwd: "/tmp/liney-shell-session-tmux"),
                surfaceController: surface
            )

            session.title = "tmux"
            let snapshot = session.snapshot()

            XCTAssertEqual(snapshot.backendConfiguration.kind, .localShell)
            XCTAssertEqual(snapshot.backendConfiguration.localShell?.shellArguments, ["-lc", "tmux attach || tmux"])
        }
    }

    func testSnapshotPromotesSSHSessionToRestorableTmuxAttach() async {
        await MainActor.run {
            let surface = FakeManagedTerminalSurfaceController()
            let session = ShellSession(
                snapshot: PaneSnapshot(
                    id: UUID(),
                    preferredWorkingDirectory: "/srv/app",
                    preferredEngine: .libghosttyPreferred,
                    backendConfiguration: .ssh(
                        SSHSessionConfiguration(
                            host: "example.com",
                            user: "dev",
                            port: nil,
                            identityFilePath: nil,
                            remoteWorkingDirectory: "/srv/app",
                            remoteCommand: nil
                        )
                    )
                ),
                surfaceController: surface
            )

            session.title = "tmux"
            let snapshot = session.snapshot()

            XCTAssertEqual(snapshot.backendConfiguration.kind, .ssh)
            XCTAssertEqual(snapshot.backendConfiguration.ssh?.remoteCommand, "tmux attach || tmux")
        }
    }

    func testProcessReaperTerminatesShellProcessGroupAndLoginProcess() throws {
        let metadataDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: metadataDirectory) }

        let metadataPath = metadataDirectory.appendingPathComponent("session.env").path
        try """
        shell_pid=321
        login_pid=123
        tty=/dev/ttys099
        """.write(toFile: metadataPath, atomically: true, encoding: .utf8)

        let launchConfiguration = TerminalLaunchConfiguration(
            workingDirectory: "/tmp",
            environment: [LineyTerminalManagedProcessReaper.metadataPathEnvironmentKey: metadataPath],
            command: TerminalCommandDefinition(
                executablePath: "/bin/zsh",
                arguments: ["-l"],
                displayName: "zsh"
            ),
            backendConfiguration: .local()
        )

        var signals: [(pid: Int32, signal: Int32)] = []
        let processControl = LineyTerminalManagedProcessControl(
            processGroupID: { pid in
                XCTAssertEqual(pid, 321)
                return 777
            },
            sendSignal: { pid, signal in
                signals.append((pid, signal))
                return 0
            }
        )

        LineyTerminalManagedProcessReaper.reap(
            launchConfiguration,
            fileManager: .default,
            processControl: processControl
        )

        XCTAssertEqual(signals.map(\.pid), [-777, 321, 123])
        XCTAssertEqual(signals.map(\.signal), [SIGTERM, SIGTERM, SIGTERM])
        XCTAssertFalse(FileManager.default.fileExists(atPath: metadataPath))
    }
}

@MainActor
private final class FakeManagedTerminalSurfaceController: ManagedTerminalSessionSurfaceController {
    let resolvedEngine: TerminalEngineKind = .libghosttyPreferred
    let view = NSView()

    var onResize: ((Int, Int) -> Void)?
    var onTitleChange: ((String) -> Void)?
    var onWorkingDirectoryChange: ((String?) -> Void)?
    var onFocus: (() -> Void)?
    var onStatusChange: ((TerminalSurfaceStatusSnapshot) -> Void)?
    var onProcessExit: ((Int32?) -> Void)?

    var managedPID: Int32? = nil
    var isManagedSessionRunning = false
    var needsConfirmQuit = false

    private(set) var startCallCount = 0
    private(set) var restartCallCount = 0
    private(set) var terminateCallCount = 0
    private(set) var sentTexts: [String] = []
    private(set) var sendReturnCallCount = 0

    func updateLaunchConfiguration(_ configuration: TerminalLaunchConfiguration) {}

    func startManagedSessionIfNeeded() {
        startCallCount += 1
        isManagedSessionRunning = true
        managedPID = 4242
    }

    func restartManagedSession() {
        restartCallCount += 1
        isManagedSessionRunning = true
        managedPID = 5252
    }

    func terminateManagedSession() {
        terminateCallCount += 1
        isManagedSessionRunning = false
        managedPID = nil
    }

    func sendText(_ text: String) {
        sentTexts.append(text)
    }
    func sendReturn() {
        sendReturnCallCount += 1
    }
    func focus() {}
    func setFocused(_ isFocused: Bool) {}
    func beginSearch(initialText: String?) {}
    func updateSearch(_ text: String) {}
    func searchNext() {}
    func searchPrevious() {}
    func endSearch() {}
    func toggleReadOnly() {}

    func emitProcessExit(_ exitCode: Int32?) {
        needsConfirmQuit = false
        isManagedSessionRunning = false
        managedPID = nil
        onProcessExit?(exitCode)
    }
}
