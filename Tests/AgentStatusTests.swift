//
//  AgentStatusTests.swift
//  LineyTests
//
//  Author: everettjf
//

import XCTest
@testable import Liney

final class AgentReportedStateTests: XCTestCase {
    func testCanonicalValuesParse() {
        XCTAssertEqual(AgentReportedState(cliValue: "running"), .running)
        XCTAssertEqual(AgentReportedState(cliValue: "waiting"), .waiting)
        XCTAssertEqual(AgentReportedState(cliValue: "done"), .done)
        XCTAssertEqual(AgentReportedState(cliValue: "error"), .error)
    }

    func testSynonymsParse() {
        XCTAssertEqual(AgentReportedState(cliValue: "blocked"), .waiting)
        XCTAssertEqual(AgentReportedState(cliValue: "needs-input"), .waiting)
        XCTAssertEqual(AgentReportedState(cliValue: "finished"), .done)
        XCTAssertEqual(AgentReportedState(cliValue: "failed"), .error)
        XCTAssertEqual(AgentReportedState(cliValue: "busy"), .running)
    }

    func testParsingIsCaseInsensitive() {
        XCTAssertEqual(AgentReportedState(cliValue: "WAITING"), .waiting)
        XCTAssertEqual(AgentReportedState(cliValue: "Error"), .error)
    }

    func testUnknownValueReturnsNil() {
        XCTAssertNil(AgentReportedState(cliValue: "banana"))
        XCTAssertNil(AgentReportedState(cliValue: ""))
    }

    func testIslandStatusMapping() {
        XCTAssertEqual(AgentReportedState.running.islandStatus, .running)
        XCTAssertEqual(AgentReportedState.waiting.islandStatus, .waitingForInput)
        XCTAssertEqual(AgentReportedState.done.islandStatus, .done)
        XCTAssertEqual(AgentReportedState.error.islandStatus, .error)
    }
}

final class AgentStatusStoreTests: XCTestCase {
    func testUpdateAndReadBack() {
        let store = AgentStatusStore(now: { Date(timeIntervalSince1970: 100) })
        let pane = UUID()
        store.update(pane: pane, state: .waiting, title: "Needs approval")
        XCTAssertEqual(store.state(for: pane), .waiting)
        XCTAssertEqual(store.entries[pane]?.title, "Needs approval")
        XCTAssertEqual(store.entries[pane]?.updatedAt, Date(timeIntervalSince1970: 100))
    }

    func testLastWriteWins() {
        let store = AgentStatusStore()
        let pane = UUID()
        store.update(pane: pane, state: .running, title: nil)
        store.update(pane: pane, state: .done, title: "Finished")
        XCTAssertEqual(store.state(for: pane), .done)
        XCTAssertEqual(store.entries.count, 1)
    }

    func testClearRemovesEntry() {
        let store = AgentStatusStore()
        let pane = UUID()
        store.update(pane: pane, state: .error, title: nil)
        store.clear(pane: pane)
        XCTAssertNil(store.state(for: pane))
    }

    func testUnknownPaneReadsNil() {
        let store = AgentStatusStore()
        XCTAssertNil(store.state(for: UUID()))
    }
}
