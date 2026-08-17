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

    func testStructuredDiagnosticEntryIncludesPaneSessionAndSurfaceContext() {
        let paneID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let sessionID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let diagnostics = TerminalDiagnostics.shared
        diagnostics.clear()

        diagnostics.record(
            event: "metrics",
            context: TerminalDiagnosticContext(paneID: paneID, sessionID: sessionID, surfaceID: "surface01"),
            attributes: ["reason": "layout", "refreshed": "true"]
        )

        let message = diagnostics.entries.last?.message ?? ""
        XCTAssertTrue(message.contains("pane=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"))
        XCTAssertTrue(message.contains("session=11111111-2222-3333-4444-555555555555"))
        XCTAssertTrue(message.contains("surface=surface01"))
        XCTAssertTrue(message.contains("event=metrics"))
        XCTAssertTrue(message.contains("reason=layout"))
    }

    func testTerminalDiagnosticIssueURLPrefillsEnvironmentAndAttachmentInstructions() throws {
        let metadata = TerminalDiagnosticReportMetadata(
            appVersion: "1.2.3",
            appBuild: "45",
            macOSVersion: "macOS 15.7",
            architecture: "arm64",
            ghosttyVersion: "1.3.2"
        )
        let url = try XCTUnwrap(
            terminalDiagnosticIssueURL(metadata: metadata, attachmentName: "Liney-Diagnostics.log")
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let body = components.queryItems?.first(where: { $0.name == "body" })?.value ?? ""

        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.path, "/everettjf/liney/issues/new")
        XCTAssertTrue(body.contains("Liney-Diagnostics.log"))
        XCTAssertTrue(body.contains("macOS 15.7"))
        XCTAssertTrue(body.contains("terminal input is not recorded"))
    }

    func testDiagnosticAttachmentWriterCreatesShareableLog() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = try writeTerminalDiagnosticAttachment(report: "diagnostic-report", directory: directory)

        XCTAssertEqual(url.pathExtension, "log")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "diagnostic-report")
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
