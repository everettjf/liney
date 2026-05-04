//
//  ListeningPortInspectorTests.swift
//  LineyTests
//
//  Author: everettjf
//

import XCTest
@testable import Liney

final class ListeningPortInspectorTests: XCTestCase {
    func testParseExtractsTCPListenerPortAndCommand() {
        let lsofOutput = """
        COMMAND  PID    USER FD TYPE DEVICE SIZE/OFF NODE NAME
        node     1234   eve  20u IPv4 0xabc      0t0 TCP *:3000 (LISTEN)
        """
        let result = ListeningPortInspector.parse(lsofOutput)
        XCTAssertEqual(result.ports, [3000])
        XCTAssertEqual(result.processNames, ["node"])
    }

    func testParseDeduplicatesAcrossRows() {
        // Two protocols (IPv4 + IPv6) on the same port appear as two lines.
        let lsofOutput = """
        node 9 eve 20u IPv4 0x1 0t0 TCP *:3000 (LISTEN)
        node 9 eve 21u IPv6 0x2 0t0 TCP *:3000 (LISTEN)
        """
        let result = ListeningPortInspector.parse(lsofOutput)
        XCTAssertEqual(result.ports, [3000])
    }

    func testParseHandlesIPv6BracketSyntax() {
        let lsofOutput = "vite 100 eve 20u IPv6 0x1 0t0 TCP [::1]:5173 (LISTEN)"
        let result = ListeningPortInspector.parse(lsofOutput)
        XCTAssertEqual(result.ports, [5173])
        XCTAssertEqual(result.processNames, ["vite"])
    }

    func testParseHandlesLoopbackAddress() {
        let lsofOutput = "ruby 1 eve 20u IPv4 0x1 0t0 TCP 127.0.0.1:8080 (LISTEN)"
        let result = ListeningPortInspector.parse(lsofOutput)
        XCTAssertEqual(result.ports, [8080])
    }

    func testParseSortsPortsAscendingAndCollectsDistinctCommands() {
        let lsofOutput = """
        vite 100 eve 20u IPv4 0x1 0t0 TCP *:5173 (LISTEN)
        node 200 eve 20u IPv4 0x2 0t0 TCP *:3000 (LISTEN)
        """
        let result = ListeningPortInspector.parse(lsofOutput)
        XCTAssertEqual(result.ports, [3000, 5173])
        XCTAssertEqual(result.processNames, ["node", "vite"])
    }

    func testParseSkipsHeaderRow() {
        let lsofOutput = "COMMAND  PID    USER FD TYPE DEVICE SIZE/OFF NODE NAME"
        let result = ListeningPortInspector.parse(lsofOutput)
        XCTAssertTrue(result.ports.isEmpty)
        XCTAssertTrue(result.processNames.isEmpty)
    }

    func testParseListenPortHandlesArrowSuffix() {
        // Defensive: even though `-sTCP:LISTEN` excludes ESTABLISHED rows, make
        // sure stray arrow-shaped names don't pollute the parser.
        XCTAssertEqual(ListeningPortInspector.parseListenPort(from: "127.0.0.1:54321->127.0.0.1:3000"), 54321)
    }

    // MARK: - Sidebar badge formatter

    func testBadgeTextHidesNothingForSmallList() {
        XCTAssertEqual(lineySidebarListeningPortsBadgeText([3000]), ":3000")
        XCTAssertEqual(lineySidebarListeningPortsBadgeText([3000, 8080]), ":3000 :8080")
    }

    func testBadgeTextCollapsesLongLists() {
        XCTAssertEqual(lineySidebarListeningPortsBadgeText([3000, 4000, 5000, 6000]), ":3000 :4000 +2")
    }

    func testBadgeTextEmptyForEmptyInput() {
        XCTAssertEqual(lineySidebarListeningPortsBadgeText([]), "")
    }
}
