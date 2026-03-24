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
    func testLocalShellDefaultUsesResolvedLoginShellPath() {
        let configuration = LocalShellSessionConfiguration.fromLoginShellPath("/opt/homebrew/bin/fish")

        XCTAssertEqual(configuration.shellPath, "/opt/homebrew/bin/fish")
        XCTAssertEqual(configuration.shellArguments, ["-l"])
    }

    func testLocalShellDefaultFallsBackToLegacyZshWhenLoginShellIsUnavailable() {
        let configuration = LocalShellSessionConfiguration.fromLoginShellPath(nil)

        XCTAssertEqual(configuration, .legacyDefault)
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

    func testStartIfNeededOnlyAutoStartsIdleSession() async {
        await MainActor.run {
            let surface = FakeManagedTerminalSurfaceController()
            let session = ShellSession(
                snapshot: PaneSnapshot.makeDefault(cwd: "/tmp/liney-shell-session"),
                surfaceController: surface
            )

            XCTAssertEqual(session.lifecycle, .idle)
            XCTAssertFalse(session.hasActiveProcess)

            session.startIfNeeded()

            XCTAssertEqual(surface.startCallCount, 1)
            XCTAssertEqual(session.lifecycle, .running)
            XCTAssertTrue(session.hasActiveProcess)
            XCTAssertEqual(session.pid, surface.managedPID)

            surface.emitProcessExit(7)

            XCTAssertEqual(session.lifecycle, .exited)
            XCTAssertFalse(session.hasActiveProcess)
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

    private(set) var startCallCount = 0
    private(set) var restartCallCount = 0
    private(set) var terminateCallCount = 0

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

    func sendText(_ text: String) {}
    func focus() {}
    func setFocused(_ isFocused: Bool) {}
    func beginSearch(initialText: String?) {}
    func updateSearch(_ text: String) {}
    func searchNext() {}
    func searchPrevious() {}
    func endSearch() {}
    func toggleReadOnly() {}

    func emitProcessExit(_ exitCode: Int32?) {
        isManagedSessionRunning = false
        managedPID = nil
        onProcessExit?(exitCode)
    }
}
