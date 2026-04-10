//
//  TmuxRestoreTests.swift
//  LineyTests
//
//  Author: everettjf
//

import XCTest
@testable import Liney

final class TmuxRestoreTests: XCTestCase {

    // MARK: - Local shell → tmux attach

    func testTmuxRestoreReplacesLocalShellWithTmuxAttach() {
        let snapshot = PaneSnapshot(
            id: UUID(),
            preferredWorkingDirectory: "/tmp",
            preferredEngine: .libghosttyPreferred,
            backendConfiguration: .local(),
            detectedTmuxSession: "myproject"
        )

        let restored = WorkspaceSessionController.applyTmuxRestore(to: snapshot)

        XCTAssertEqual(restored.backendConfiguration.kind, .tmuxAttach)
        XCTAssertEqual(restored.backendConfiguration.tmuxAttach?.sessionName, "myproject")
        XCTAssertEqual(restored.backendConfiguration.tmuxAttach?.isRemote, false)
        XCTAssertNil(restored.backendConfiguration.tmuxAttach?.sshConfig)
        XCTAssertNil(restored.backendConfiguration.tmuxAttach?.windowIndex)
        XCTAssertEqual(restored.id, snapshot.id)
    }

    // MARK: - SSH → remote tmux attach

    func testTmuxRestoreReplacesSSHWithRemoteTmuxAttach() {
        let sshConfig = SSHSessionConfiguration(
            host: "dev.example.com",
            user: "deploy",
            port: 2222,
            identityFilePath: "~/.ssh/id_ed25519",
            remoteWorkingDirectory: "/opt/app",
            remoteCommand: nil
        )
        let snapshot = PaneSnapshot(
            id: UUID(),
            preferredWorkingDirectory: "/tmp",
            preferredEngine: .libghosttyPreferred,
            backendConfiguration: .ssh(sshConfig),
            detectedTmuxSession: "remotedev"
        )

        let restored = WorkspaceSessionController.applyTmuxRestore(to: snapshot)

        XCTAssertEqual(restored.backendConfiguration.kind, .tmuxAttach)
        XCTAssertEqual(restored.backendConfiguration.tmuxAttach?.sessionName, "remotedev")
        XCTAssertEqual(restored.backendConfiguration.tmuxAttach?.isRemote, true)
        XCTAssertEqual(restored.backendConfiguration.tmuxAttach?.sshConfig, sshConfig)
        XCTAssertNil(restored.backendConfiguration.tmuxAttach?.windowIndex)
    }

    // MARK: - No tmux session → no change

    func testTmuxRestoreDoesNothingWithoutTmuxSession() {
        let snapshot = PaneSnapshot(
            id: UUID(),
            preferredWorkingDirectory: "/tmp",
            preferredEngine: .libghosttyPreferred,
            backendConfiguration: .local(),
            detectedTmuxSession: nil
        )

        let restored = WorkspaceSessionController.applyTmuxRestore(to: snapshot)

        XCTAssertEqual(restored.backendConfiguration.kind, .localShell)
        XCTAssertEqual(restored, snapshot)
    }

    // MARK: - Agent backend → no change even with tmux session

    func testTmuxRestoreDoesNothingForAgentBackend() {
        let agentConfig = AgentSessionConfiguration(
            name: "Test Agent",
            launchPath: "/usr/bin/env",
            arguments: ["python3"],
            environment: [:],
            workingDirectory: nil
        )
        let snapshot = PaneSnapshot(
            id: UUID(),
            preferredWorkingDirectory: "/tmp",
            preferredEngine: .libghosttyPreferred,
            backendConfiguration: .agent(agentConfig),
            detectedTmuxSession: "shouldbeignored"
        )

        let restored = WorkspaceSessionController.applyTmuxRestore(to: snapshot)

        XCTAssertEqual(restored.backendConfiguration.kind, .agent)
        XCTAssertEqual(restored, snapshot)
    }

    // MARK: - tmuxAttach backend → no change (already tmux)

    func testTmuxRestoreDoesNothingForExistingTmuxAttachBackend() {
        let tmuxConfig = TmuxAttachConfiguration(
            sessionName: "existing",
            windowIndex: 1,
            isRemote: false,
            sshConfig: nil
        )
        let snapshot = PaneSnapshot(
            id: UUID(),
            preferredWorkingDirectory: "/tmp",
            preferredEngine: .libghosttyPreferred,
            backendConfiguration: .tmuxAttach(tmuxConfig),
            detectedTmuxSession: "anotherone"
        )

        let restored = WorkspaceSessionController.applyTmuxRestore(to: snapshot)

        XCTAssertEqual(restored.backendConfiguration.kind, .tmuxAttach)
        // Should keep the original tmux config, not replace with detected session
        XCTAssertEqual(restored.backendConfiguration.tmuxAttach?.sessionName, "existing")
        XCTAssertEqual(restored.backendConfiguration.tmuxAttach?.windowIndex, 1)
    }

    // MARK: - Preserves other snapshot fields

    func testTmuxRestorePreservesOtherSnapshotFields() {
        let id = UUID()
        let snapshot = PaneSnapshot(
            id: id,
            preferredWorkingDirectory: "/Users/test/project",
            preferredEngine: .libghosttyPreferred,
            backendConfiguration: .local(),
            detectedTmuxSession: "dev"
        )

        let restored = WorkspaceSessionController.applyTmuxRestore(to: snapshot)

        XCTAssertEqual(restored.id, id)
        XCTAssertEqual(restored.preferredWorkingDirectory, "/Users/test/project")
        XCTAssertEqual(restored.preferredEngine, .libghosttyPreferred)
        XCTAssertEqual(restored.detectedTmuxSession, "dev")
    }
}
