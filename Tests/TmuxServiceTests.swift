import XCTest
@testable import Liney

final class TmuxServiceTests: XCTestCase {

    // MARK: - parseSessions with valid output

    func testParseSessionsWithValidOutput() {
        let output = "main\t3\t1\t1700000000\nwork\t5\t0\t1700001000\n"
        let sessions = TmuxService.parseSessions(output)

        XCTAssertEqual(sessions.count, 2)

        XCTAssertEqual(sessions[0].name, "main")
        XCTAssertEqual(sessions[0].windowCount, 3)
        XCTAssertTrue(sessions[0].isAttached)
        XCTAssertEqual(sessions[0].createdAt, Date(timeIntervalSince1970: 1700000000))
        XCTAssertEqual(sessions[0].id, "main")

        XCTAssertEqual(sessions[1].name, "work")
        XCTAssertEqual(sessions[1].windowCount, 5)
        XCTAssertFalse(sessions[1].isAttached)
        XCTAssertEqual(sessions[1].createdAt, Date(timeIntervalSince1970: 1700001000))
        XCTAssertEqual(sessions[1].id, "work")
    }

    func testParseSessionsSingleSession() {
        let output = "dev\t1\t0\t1699999999\n"
        let sessions = TmuxService.parseSessions(output)

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].name, "dev")
        XCTAssertEqual(sessions[0].windowCount, 1)
        XCTAssertFalse(sessions[0].isAttached)
        XCTAssertNotNil(sessions[0].createdAt)
    }

    // MARK: - parseSessions with empty output

    func testParseSessionsEmptyOutput() {
        let sessions = TmuxService.parseSessions("")
        XCTAssertTrue(sessions.isEmpty)
    }

    func testParseSessionsWhitespaceOnlyOutput() {
        let sessions = TmuxService.parseSessions("   \n  \n")
        XCTAssertTrue(sessions.isEmpty)
    }

    // MARK: - parseSessions with malformed lines

    func testParseSessionsMalformedTooFewFields() {
        let output = "main\t3\n"
        let sessions = TmuxService.parseSessions(output)
        XCTAssertTrue(sessions.isEmpty)
    }

    func testParseSessionsMalformedNonNumericWindowCount() {
        let output = "main\tabc\t1\t1700000000\n"
        let sessions = TmuxService.parseSessions(output)
        XCTAssertTrue(sessions.isEmpty)
    }

    func testParseSessionsMalformedMixedValidAndInvalid() {
        let output = "valid\t2\t1\t1700000000\nbad\n\ngood\t4\t0\t1700002000\n"
        let sessions = TmuxService.parseSessions(output)

        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].name, "valid")
        XCTAssertEqual(sessions[1].name, "good")
    }

    func testParseSessionsInvalidTimestamp() {
        let output = "test\t1\t0\tnot-a-number\n"
        let sessions = TmuxService.parseSessions(output)

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].name, "test")
        XCTAssertNil(sessions[0].createdAt)
    }

    // MARK: - attachCommand format

    func testAttachCommand() {
        let service = TmuxService()
        let command = service.attachCommand(for: "mysession")
        XCTAssertEqual(command, "tmux attach-session -t mysession")
    }

    func testAttachCommandWithSpecialName() {
        let service = TmuxService()
        let command = service.attachCommand(for: "my-session-123")
        XCTAssertEqual(command, "tmux attach-session -t my-session-123")
    }

    // MARK: - remoteAttachCommand format

    func testRemoteAttachCommandWithUserAndCustomPort() {
        let service = TmuxService()
        let config = SSHSessionConfiguration(
            host: "example.com",
            user: "deploy",
            port: 2222
        )
        let command = service.remoteAttachCommand(for: "prod", via: config)
        XCTAssertEqual(command, "ssh -p 2222 -t deploy@example.com tmux attach-session -t prod")
    }

    func testRemoteAttachCommandWithDefaultPort() {
        let service = TmuxService()
        let config = SSHSessionConfiguration(
            host: "example.com",
            user: "admin",
            port: 22
        )
        let command = service.remoteAttachCommand(for: "dev", via: config)
        // Default port 22 should not produce a -p flag
        XCTAssertEqual(command, "ssh -t admin@example.com tmux attach-session -t dev")
        XCTAssertFalse(command.contains("-p"))
    }

    func testRemoteAttachCommandWithNilPort() {
        let service = TmuxService()
        let config = SSHSessionConfiguration(
            host: "myserver.local",
            user: "user"
        )
        let command = service.remoteAttachCommand(for: "session1", via: config)
        XCTAssertEqual(command, "ssh -t user@myserver.local tmux attach-session -t session1")
        XCTAssertFalse(command.contains("-p"))
    }

    func testRemoteAttachCommandWithoutUser() {
        let service = TmuxService()
        let config = SSHSessionConfiguration(
            host: "192.168.1.100"
        )
        let command = service.remoteAttachCommand(for: "main", via: config)
        XCTAssertEqual(command, "ssh -t 192.168.1.100 tmux attach-session -t main")
    }

    func testRemoteAttachCommandWithIdentityFile() {
        let service = TmuxService()
        let config = SSHSessionConfiguration(
            host: "example.com",
            user: "deploy",
            port: 2222,
            identityFilePath: "~/.ssh/id_ed25519"
        )
        let command = service.remoteAttachCommand(for: "prod", via: config)
        XCTAssertEqual(command, "ssh -p 2222 -i ~/.ssh/id_ed25519 -t deploy@example.com tmux attach-session -t prod")
    }
}
