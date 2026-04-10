import XCTest
@testable import Liney

final class SessionBackendTmuxTests: XCTestCase {

    // MARK: - TmuxAttachConfiguration Codable round-trip

    func testTmuxAttachConfigurationCodableRoundTrip() throws {
        let config = TmuxAttachConfiguration(
            sessionName: "my-session",
            windowIndex: 2,
            isRemote: true,
            sshConfig: SSHSessionConfiguration(
                host: "example.com",
                user: "deploy",
                port: 2222,
                identityFilePath: "~/.ssh/id_ed25519",
                remoteWorkingDirectory: nil,
                remoteCommand: nil
            )
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(TmuxAttachConfiguration.self, from: data)

        XCTAssertEqual(decoded, config)
        XCTAssertEqual(decoded.sessionName, "my-session")
        XCTAssertEqual(decoded.windowIndex, 2)
        XCTAssertTrue(decoded.isRemote)
        XCTAssertEqual(decoded.sshConfig?.host, "example.com")
        XCTAssertEqual(decoded.sshConfig?.user, "deploy")
        XCTAssertEqual(decoded.sshConfig?.port, 2222)
    }

    func testTmuxAttachConfigurationCodableWithNilOptionals() throws {
        let config = TmuxAttachConfiguration(
            sessionName: "dev",
            windowIndex: nil,
            isRemote: false,
            sshConfig: nil
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(TmuxAttachConfiguration.self, from: data)

        XCTAssertEqual(decoded, config)
        XCTAssertNil(decoded.windowIndex)
        XCTAssertFalse(decoded.isRemote)
        XCTAssertNil(decoded.sshConfig)
    }

    // MARK: - SessionBackendConfiguration.tmuxAttach factory

    func testTmuxAttachFactoryCreatesCorrectKind() {
        let config = SessionBackendConfiguration.tmuxAttach(
            TmuxAttachConfiguration(
                sessionName: "work",
                windowIndex: nil,
                isRemote: false,
                sshConfig: nil
            )
        )

        XCTAssertEqual(config.kind, .tmuxAttach)
        XCTAssertNotNil(config.tmuxAttach)
        XCTAssertEqual(config.tmuxAttach?.sessionName, "work")
        XCTAssertNil(config.localShell)
        XCTAssertNil(config.ssh)
        XCTAssertNil(config.agent)
    }

    // MARK: - SessionBackendConfiguration with tmuxAttach Codable round-trip

    func testSessionBackendConfigurationTmuxAttachCodableRoundTrip() throws {
        let config = SessionBackendConfiguration.tmuxAttach(
            TmuxAttachConfiguration(
                sessionName: "prod",
                windowIndex: 0,
                isRemote: true,
                sshConfig: SSHSessionConfiguration(
                    host: "server.local",
                    user: "admin",
                    port: nil,
                    identityFilePath: nil,
                    remoteWorkingDirectory: nil,
                    remoteCommand: nil
                )
            )
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(SessionBackendConfiguration.self, from: data)

        XCTAssertEqual(decoded.kind, .tmuxAttach)
        XCTAssertEqual(decoded.tmuxAttach?.sessionName, "prod")
        XCTAssertEqual(decoded.tmuxAttach?.windowIndex, 0)
        XCTAssertTrue(decoded.tmuxAttach?.isRemote == true)
        XCTAssertEqual(decoded.tmuxAttach?.sshConfig?.host, "server.local")
    }

    // MARK: - displayName contains session name

    func testDisplayNameContainsSessionName() {
        let config = SessionBackendConfiguration.tmuxAttach(
            TmuxAttachConfiguration(
                sessionName: "my-project",
                windowIndex: nil,
                isRemote: false,
                sshConfig: nil
            )
        )

        XCTAssertTrue(config.displayName.contains("my-project"))
        XCTAssertTrue(config.displayName.hasPrefix("tmux:"))
    }

    // MARK: - Backward compatibility: old JSON without tmuxAttach decodes fine

    func testBackwardCompatibilityOldJSONWithoutTmuxAttach() throws {
        let oldJSON = """
        {
            "kind": "localShell",
            "localShell": {
                "shellPath": "/bin/zsh",
                "shellArguments": ["-l"]
            }
        }
        """

        let data = oldJSON.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SessionBackendConfiguration.self, from: data)

        XCTAssertEqual(decoded.kind, .localShell)
        XCTAssertNotNil(decoded.localShell)
        XCTAssertNil(decoded.tmuxAttach)
    }

    func testBackwardCompatibilityOldSSHJSONWithoutTmuxAttach() throws {
        let oldJSON = """
        {
            "kind": "ssh",
            "ssh": {
                "host": "example.com",
                "user": "test"
            }
        }
        """

        let data = oldJSON.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SessionBackendConfiguration.self, from: data)

        XCTAssertEqual(decoded.kind, .ssh)
        XCTAssertNotNil(decoded.ssh)
        XCTAssertNil(decoded.tmuxAttach)
        XCTAssertNil(decoded.localShell)
    }

    // MARK: - SessionBackendKind tmuxAttach

    func testSessionBackendKindTmuxAttachExists() {
        let kind = SessionBackendKind.tmuxAttach
        XCTAssertEqual(kind.rawValue, "tmuxAttach")
        XCTAssertFalse(kind.displayName.isEmpty)
    }

    func testSessionBackendKindCaseIterableIncludesTmuxAttach() {
        XCTAssertTrue(SessionBackendKind.allCases.contains(.tmuxAttach))
    }
}
