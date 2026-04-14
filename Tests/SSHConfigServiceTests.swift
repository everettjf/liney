import XCTest
@testable import Liney

final class SSHConfigServiceTests: XCTestCase {

    // MARK: - SSHConnectionStatus enum

    func testConnectedCaseExists() {
        let status: SSHConnectionStatus = .connected
        if case .connected = status {
            // pass
        } else {
            XCTFail("Expected .connected")
        }
    }

    func testAuthRequiredCaseExists() {
        let status: SSHConnectionStatus = .authRequired
        if case .authRequired = status {
            // pass
        } else {
            XCTFail("Expected .authRequired")
        }
    }

    func testUnreachableCaseExists() {
        struct DummyError: Error {}
        let status: SSHConnectionStatus = .unreachable(DummyError())
        if case .unreachable(let error) = status {
            XCTAssertTrue(error is DummyError)
        } else {
            XCTFail("Expected .unreachable")
        }
    }

    func testStatusPatternMatchingSwitch() {
        struct TestError: Error {}
        let statuses: [SSHConnectionStatus] = [
            .connected,
            .authRequired,
            .unreachable(TestError()),
        ]

        for status in statuses {
            switch status {
            case .connected:
                break
            case .authRequired:
                break
            case .unreachable:
                break
            }
        }
        // If we reach here, all cases are exhaustively matched
    }

    // MARK: - SSHConfigService

    func testLoadSSHConfigReturnsWithoutCrashing() async {
        let service = SSHConfigService()
        let entries = await service.loadSSHConfig()
        // Should not crash; result may be empty if ~/.ssh/config doesn't exist
        XCTAssertNotNil(entries)
    }

    func testLoadSSHConfigWithNonexistentPathReturnsEmpty() async {
        let service = SSHConfigService()
        let entries = await service.loadSSHConfig(configPaths: ["/nonexistent/path/config"])
        XCTAssertTrue(entries.isEmpty)
    }

    func testLoadSSHConfigWithMultiplePaths() async {
        let service = SSHConfigService()
        let entries = await service.loadSSHConfig(configPaths: [
            "/nonexistent/path1/config",
            "/nonexistent/path2/config",
        ])
        XCTAssertTrue(entries.isEmpty)
    }

    func testConnectionToUnreachableHostReturnsNonConnected() async {
        let service = SSHConfigService()
        let entry = SSHConfigEntry(
            displayName: "unreachable-test",
            host: "192.0.2.1",  // TEST-NET address, guaranteed unreachable
            port: 22,
            user: "nobody",
            identityFile: nil
        )
        let status = await service.testConnection(entry)
        // Should not be .connected since we cannot reach this host
        if case .connected = status {
            XCTFail("Should not connect to unreachable host")
        }
    }
}
