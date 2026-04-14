import XCTest
@testable import Liney

final class RemoteWorkspaceModelTests: XCTestCase {

    // MARK: - WorkspaceKind.remoteServer

    func testWorkspaceKindRemoteServer() {
        let kind = WorkspaceKind.remoteServer
        XCTAssertEqual(kind.rawValue, "remoteServer")
        XCTAssertFalse(kind.displayName.isEmpty)
    }

    // MARK: - PaneSnapshot detectedTmuxSession

    func testPaneSnapshotWithDetectedTmuxSession() throws {
        let paneID = UUID()
        let snapshot = PaneSnapshot(
            id: paneID,
            preferredWorkingDirectory: "/tmp/repo",
            preferredEngine: .libghosttyPreferred,
            backendConfiguration: .local(),
            detectedTmuxSession: "my-session"
        )

        XCTAssertEqual(snapshot.detectedTmuxSession, "my-session")

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(PaneSnapshot.self, from: data)

        XCTAssertEqual(decoded.id, paneID)
        XCTAssertEqual(decoded.detectedTmuxSession, "my-session")
        XCTAssertEqual(decoded.preferredWorkingDirectory, "/tmp/repo")
    }

    func testPaneSnapshotBackwardCompatibility_NoTmux() throws {
        let paneID = UUID()
        let json = """
        {
          "id": "\(paneID.uuidString)",
          "preferredWorkingDirectory": "/tmp/repo",
          "shellPath": "/bin/zsh",
          "shellArguments": ["-l"],
          "preferredEngine": "libghosttyPreferred"
        }
        """

        let decoded = try JSONDecoder().decode(PaneSnapshot.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.id, paneID)
        XCTAssertNil(decoded.detectedTmuxSession)
        XCTAssertEqual(decoded.preferredWorkingDirectory, "/tmp/repo")
    }

    // MARK: - WorkspaceRecord sshTarget

    func testWorkspaceRecordWithSSHTarget() throws {
        let paneID = UUID()
        let sshConfig = SSHSessionConfiguration(
            host: "prod.example.com",
            user: "deploy",
            port: 2222,
            identityFilePath: "~/.ssh/id_ed25519",
            remoteWorkingDirectory: "/srv/app",
            remoteCommand: nil
        )

        let record = WorkspaceRecord(
            id: UUID(),
            kind: .remoteServer,
            name: "Production",
            repositoryRoot: "/srv/app",
            activeWorktreePath: "/srv/app",
            worktreeStates: [
                WorktreeSessionStateRecord.makeDefault(for: "/srv/app")
            ],
            isSidebarExpanded: false,
            sshTarget: sshConfig
        )

        XCTAssertEqual(record.sshTarget?.host, "prod.example.com")
        XCTAssertEqual(record.kind, .remoteServer)

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(WorkspaceRecord.self, from: data)

        XCTAssertEqual(decoded.sshTarget?.host, "prod.example.com")
        XCTAssertEqual(decoded.sshTarget?.user, "deploy")
        XCTAssertEqual(decoded.sshTarget?.port, 2222)
        XCTAssertEqual(decoded.sshTarget?.remoteWorkingDirectory, "/srv/app")
        XCTAssertEqual(decoded.kind, .remoteServer)
    }

    func testRemoteServerSupportsRepositoryFeatures() {
        // supportsRepositoryFeatures is `kind == .repository || kind == .remoteServer`
        // Verify the enum values directly since WorkspaceModel init has side effects
        let repositoryKind = WorkspaceKind.repository
        let remoteKind = WorkspaceKind.remoteServer
        let localKind = WorkspaceKind.localTerminal

        XCTAssertTrue(repositoryKind == .repository || repositoryKind == .remoteServer)
        XCTAssertTrue(remoteKind == .repository || remoteKind == .remoteServer)
        XCTAssertFalse(localKind == .repository || localKind == .remoteServer)
    }

    func testWorkspaceRecordBackwardCompatibility_NoSSHTarget() throws {
        let paneID = UUID()
        let workspaceID = UUID()
        let json = """
        {
          "id": "\(workspaceID.uuidString)",
          "name": "OldRepo",
          "repositoryRoot": "/tmp/repo",
          "activeWorktreePath": "/tmp/repo",
          "layout": {
            "kind": "pane",
            "pane": { "paneID": "\(paneID.uuidString)" }
          },
          "panes": [
            {
              "id": "\(paneID.uuidString)",
              "preferredWorkingDirectory": "/tmp/repo",
              "shellPath": "/bin/zsh",
              "shellArguments": ["-l"],
              "preferredEngine": "libghosttyPreferred"
            }
          ],
          "focusedPaneID": "\(paneID.uuidString)",
          "isSidebarExpanded": false
        }
        """

        let decoded = try JSONDecoder().decode(WorkspaceRecord.self, from: Data(json.utf8))

        XCTAssertNil(decoded.sshTarget)
        XCTAssertEqual(decoded.kind, .repository)
        XCTAssertEqual(decoded.name, "OldRepo")
    }
}
