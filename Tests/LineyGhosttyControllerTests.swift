//
//  LineyGhosttyControllerTests.swift
//  LineyTests
//
//  Author: Codex
//

import XCTest
import GhosttyKit
@testable import Liney

final class LineyGhosttyControllerTests: XCTestCase {
    func testTerminalDiagnosticLogStoreRetainsOnlyRecentEntries() {
        let now = Date(timeIntervalSince1970: 10_000)
        var store = TerminalDiagnosticLogStore(retentionInterval: 60 * 60, maximumEntryCount: 100)

        store.append(TerminalDiagnosticEntry(timestamp: now.addingTimeInterval(-3_601), message: "old"), now: now)
        store.append(TerminalDiagnosticEntry(timestamp: now, message: "recent"), now: now)

        XCTAssertEqual(store.entries.map(\.message), ["recent"])
    }

    func testTerminalDiagnosticLogStoreEnforcesEntryLimit() {
        let now = Date(timeIntervalSince1970: 10_000)
        var store = TerminalDiagnosticLogStore(retentionInterval: 60 * 60, maximumEntryCount: 2)

        store.append(TerminalDiagnosticEntry(timestamp: now, message: "one"), now: now)
        store.append(TerminalDiagnosticEntry(timestamp: now, message: "two"), now: now)
        store.append(TerminalDiagnosticEntry(timestamp: now, message: "three"), now: now)

        XCTAssertEqual(store.entries.map(\.message), ["two", "three"])
    }

    func testTerminalDiagnosticReportIncludesRuntimeMetadataAndLogs() {
        let report = terminalDiagnosticReport(
            metadata: TerminalDiagnosticReportMetadata(
                appVersion: "1.2.3",
                appBuild: "45",
                macOSVersion: "macOS 26.0",
                architecture: "arm64",
                ghosttyVersion: "1.3.2"
            ),
            log: "[now] surface=abc event=metrics"
        )

        XCTAssertTrue(report.contains("Liney: 1.2.3 (45)"))
        XCTAssertTrue(report.contains("Ghostty: 1.3.2"))
        XCTAssertTrue(report.contains("surface=abc event=metrics"))
        XCTAssertTrue(report.contains("terminal input is not recorded"))
    }

    func testCommandFinishedDoesNotReportProcessExit() {
        XCTAssertFalse(
            lineyGhosttyShouldReportProcessExitForCommandFinished(
                ghostty_action_command_finished_s(
                    exit_code: 0,
                    duration: 42
                )
            )
        )
    }

    func testSurfaceCloseWhileProcessIsAliveDoesNotReportProcessExit() {
        XCTAssertFalse(lineyGhosttyShouldReportProcessExitForSurfaceClose(processAlive: true))
    }

    func testSurfaceCloseAfterProcessExitReportsExit() {
        XCTAssertTrue(lineyGhosttyShouldReportProcessExitForSurfaceClose(processAlive: false))
    }

    func testSurfaceRefreshRunsWhenDisplayMetricsChange() {
        let previous = LineyGhosttySurfaceMetricsSignature(
            width: 800,
            height: 600,
            scale: 2,
            displayID: 1
        )
        let next = LineyGhosttySurfaceMetricsSignature(
            width: 800,
            height: 600,
            scale: 1,
            displayID: 2
        )

        XCTAssertTrue(lineyGhosttyShouldRefreshSurface(after: previous, next: next))
        XCTAssertFalse(lineyGhosttyShouldRefreshSurface(after: next, next: next))
    }
}
