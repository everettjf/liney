//
//  TmuxDetectionTests.swift
//  LineyTests
//
//  Author: everettjf
//

import XCTest
@testable import Liney

final class TmuxDetectionTests: XCTestCase {

    // MARK: - TmuxTitleDetector.detectSession

    func testDetectSessionWithStatusBarFormat() {
        XCTAssertEqual(
            TmuxTitleDetector.detectSession(fromTitle: "[myproject] 0:bash"),
            "myproject"
        )
    }

    func testDetectSessionWithStatusBarFormatNumericName() {
        XCTAssertEqual(
            TmuxTitleDetector.detectSession(fromTitle: "[0] 1:vim"),
            "0"
        )
    }

    func testDetectSessionWithTmuxNewDashS() {
        XCTAssertEqual(
            TmuxTitleDetector.detectSession(fromTitle: "tmux new -s hello"),
            "hello"
        )
    }

    func testDetectSessionWithTmuxAttachDashT() {
        XCTAssertEqual(
            TmuxTitleDetector.detectSession(fromTitle: "tmux attach -t mysession"),
            "mysession"
        )
    }

    func testDetectSessionWithTmuxAttachDashTWithWindowSuffix() {
        XCTAssertEqual(
            TmuxTitleDetector.detectSession(fromTitle: "tmux attach -t work:2"),
            "work"
        )
    }

    func testDetectSessionWithBareTmux() {
        XCTAssertEqual(
            TmuxTitleDetector.detectSession(fromTitle: "tmux"),
            "tmux"
        )
    }

    func testDetectSessionWithSetTitlesFormatAlphaSession() {
        XCTAssertEqual(
            TmuxTitleDetector.detectSession(fromTitle: "dev:0:bash - \"hostname\""),
            "dev"
        )
    }

    func testDetectSessionWithSetTitlesFormatNumericSession() {
        XCTAssertEqual(
            TmuxTitleDetector.detectSession(fromTitle: "13:0:bash - \"hostname\""),
            "13"
        )
    }

    func testDetectSessionWithNormalTitle() {
        XCTAssertNil(
            TmuxTitleDetector.detectSession(fromTitle: "user@hostname:~/project")
        )
    }

    func testDetectSessionWithEmptyTitle() {
        XCTAssertNil(
            TmuxTitleDetector.detectSession(fromTitle: "")
        )
    }

    func testDetectSessionWithPlainCommandTitle() {
        XCTAssertNil(
            TmuxTitleDetector.detectSession(fromTitle: "vim main.swift")
        )
    }

    // MARK: - TmuxTitleDetector.parseTmuxSessionName

    func testParseTmuxSessionNameWithDashS() {
        XCTAssertEqual(
            TmuxTitleDetector.parseTmuxSessionName(from: ["new", "-s", "hello"]),
            "hello"
        )
    }

    func testParseTmuxSessionNameWithDashT() {
        XCTAssertEqual(
            TmuxTitleDetector.parseTmuxSessionName(from: ["attach", "-t", "work"]),
            "work"
        )
    }

    func testParseTmuxSessionNameWithDashTAndWindow() {
        XCTAssertEqual(
            TmuxTitleDetector.parseTmuxSessionName(from: ["attach-session", "-t", "dev:1"]),
            "dev"
        )
    }

    func testParseTmuxSessionNameWithNewSession() {
        XCTAssertEqual(
            TmuxTitleDetector.parseTmuxSessionName(from: ["new-session", "-s", "project"]),
            "project"
        )
    }

    func testParseTmuxSessionNameWithNoSessionArg() {
        XCTAssertNil(
            TmuxTitleDetector.parseTmuxSessionName(from: ["new"])
        )
    }

    func testParseTmuxSessionNameWithEmptyArgs() {
        XCTAssertNil(
            TmuxTitleDetector.parseTmuxSessionName(from: [])
        )
    }

    func testParseTmuxSessionNameWithDashSAtEnd() {
        XCTAssertNil(
            TmuxTitleDetector.parseTmuxSessionName(from: ["new", "-s"])
        )
    }

    // MARK: - ProcessTree.parseTmuxClientList

    func testParseTmuxClientListSingleClient() {
        let output = "12345 default\n"
        let clients = ProcessTree.parseTmuxClientList(output)
        XCTAssertEqual(clients.count, 1)
        XCTAssertEqual(clients[0].clientPID, 12345)
        XCTAssertEqual(clients[0].sessionName, "default")
    }

    func testParseTmuxClientListMultipleClients() {
        let output = """
        12345 default
        67890 work
        11111 dev
        """
        let clients = ProcessTree.parseTmuxClientList(output)
        XCTAssertEqual(clients.count, 3)
        XCTAssertEqual(clients[0].clientPID, 12345)
        XCTAssertEqual(clients[0].sessionName, "default")
        XCTAssertEqual(clients[1].clientPID, 67890)
        XCTAssertEqual(clients[1].sessionName, "work")
        XCTAssertEqual(clients[2].clientPID, 11111)
        XCTAssertEqual(clients[2].sessionName, "dev")
    }

    func testParseTmuxClientListEmptyOutput() {
        let clients = ProcessTree.parseTmuxClientList("")
        XCTAssertTrue(clients.isEmpty)
    }

    func testParseTmuxClientListMalformedLine() {
        let output = "not-a-pid session\n12345 valid\n"
        let clients = ProcessTree.parseTmuxClientList(output)
        XCTAssertEqual(clients.count, 1)
        XCTAssertEqual(clients[0].clientPID, 12345)
        XCTAssertEqual(clients[0].sessionName, "valid")
    }

    func testParseTmuxClientListSessionNameWithSpaces() {
        let output = "12345 my session name\n"
        let clients = ProcessTree.parseTmuxClientList(output)
        XCTAssertEqual(clients.count, 1)
        XCTAssertEqual(clients[0].sessionName, "my session name")
    }
}
