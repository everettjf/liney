import XCTest
@testable import Liney

final class SSHConfigParserTests: XCTestCase {

    func testBasicHostEntryWithAllFields() {
        let config = """
        Host myserver
            HostName 192.168.1.100
            Port 2222
            User admin
            IdentityFile ~/.ssh/id_rsa
        """
        let entries = SSHConfigParser.parse(from: config)
        XCTAssertEqual(entries.count, 1)

        let entry = entries[0]
        XCTAssertEqual(entry.displayName, "myserver")
        XCTAssertEqual(entry.host, "192.168.1.100")
        XCTAssertEqual(entry.port, 2222)
        XCTAssertEqual(entry.user, "admin")
        XCTAssertEqual(entry.identityFile, "~/.ssh/id_rsa")
    }

    func testHostUsedAsHostNameWhenHostNameMissing() {
        let config = """
        Host example.com
            User deploy
        """
        let entries = SSHConfigParser.parse(from: config)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].displayName, "example.com")
        XCTAssertEqual(entries[0].host, "example.com")
    }

    func testWildcardHostsAreFiltered() {
        let config = """
        Host *
            ServerAliveInterval 60

        Host production
            HostName prod.example.com
        """
        let entries = SSHConfigParser.parse(from: config)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].displayName, "production")
    }

    func testQuestionMarkWildcardFiltered() {
        let config = """
        Host web?
            HostName web.example.com

        Host staging
            HostName staging.example.com
        """
        let entries = SSHConfigParser.parse(from: config)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].displayName, "staging")
    }

    func testMultipleHosts() {
        let config = """
        Host alpha
            HostName alpha.example.com
            User alice

        Host beta
            HostName beta.example.com
            User bob
            Port 3022
        """
        let entries = SSHConfigParser.parse(from: config)
        XCTAssertEqual(entries.count, 2)

        XCTAssertEqual(entries[0].displayName, "alpha")
        XCTAssertEqual(entries[0].host, "alpha.example.com")
        XCTAssertEqual(entries[0].user, "alice")

        XCTAssertEqual(entries[1].displayName, "beta")
        XCTAssertEqual(entries[1].host, "beta.example.com")
        XCTAssertEqual(entries[1].user, "bob")
        XCTAssertEqual(entries[1].port, 3022)
    }

    func testDefaultPortIs22() {
        let config = """
        Host myhost
            HostName myhost.example.com
        """
        let entries = SSHConfigParser.parse(from: config)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].port, 22)
    }

    func testEmptyConfigReturnsEmpty() {
        let entries = SSHConfigParser.parse(from: "")
        XCTAssertTrue(entries.isEmpty)
    }

    func testCommentsAndBlankLinesIgnored() {
        let config = """
        # This is a comment

        Host myserver
            # Another comment
            HostName 10.0.0.1

        # Trailing comment
        """
        let entries = SSHConfigParser.parse(from: config)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].displayName, "myserver")
        XCTAssertEqual(entries[0].host, "10.0.0.1")
    }

    func testOptionalFieldsAreNilWhenMissing() {
        let config = """
        Host minimal
            HostName minimal.example.com
        """
        let entries = SSHConfigParser.parse(from: config)
        XCTAssertEqual(entries.count, 1)
        XCTAssertNil(entries[0].user)
        XCTAssertNil(entries[0].identityFile)
    }

    func testNonexistentConfigPathReturnsEmpty() {
        let entries = SSHConfigParser.parse(configPath: "/nonexistent/path/config")
        XCTAssertTrue(entries.isEmpty)
    }

    func testTabSeparatedKeywordAndValue() {
        let config = "Host myserver\n\tHostName\t10.0.0.1\n\tPort\t2222\n\tUser\tadmin"
        let entries = SSHConfigParser.parse(from: config)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].displayName, "myserver")
        XCTAssertEqual(entries[0].host, "10.0.0.1")
        XCTAssertEqual(entries[0].port, 2222)
        XCTAssertEqual(entries[0].user, "admin")
    }

    func testEqualsSeparatedKeywordAndValue() {
        let config = """
        Host=myserver
            HostName=10.0.0.1
            Port=2222
            User = admin
        """
        let entries = SSHConfigParser.parse(from: config)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].displayName, "myserver")
        XCTAssertEqual(entries[0].host, "10.0.0.1")
        XCTAssertEqual(entries[0].port, 2222)
        XCTAssertEqual(entries[0].user, "admin")
    }

    func testMultiPatternHostLine() {
        let config = """
        Host server1 server2
            HostName shared.example.com
            User deploy
            Port 3022
        """
        let entries = SSHConfigParser.parse(from: config)
        XCTAssertEqual(entries.count, 2)

        XCTAssertEqual(entries[0].displayName, "server1")
        XCTAssertEqual(entries[0].host, "shared.example.com")
        XCTAssertEqual(entries[0].user, "deploy")
        XCTAssertEqual(entries[0].port, 3022)

        XCTAssertEqual(entries[1].displayName, "server2")
        XCTAssertEqual(entries[1].host, "shared.example.com")
        XCTAssertEqual(entries[1].user, "deploy")
        XCTAssertEqual(entries[1].port, 3022)
    }
}
