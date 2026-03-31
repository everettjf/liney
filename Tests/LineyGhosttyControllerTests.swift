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
