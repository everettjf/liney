//
//  HookRunnerTests.swift
//  LineyTests
//
//  Author: everettjf
//

import XCTest
@testable import Liney

final class HookRunnerTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("liney-hook-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        HookRunner.shared.updateMasterSwitch(false)
        HookRunner.shared.invalidateCache()
        super.tearDown()
    }

    func testFireBlockingExecutesHookAndPassesEnvironment() throws {
        // We can't redirect HookSettingsPersistence in the singleton runner from
        // outside without exposing internal state, so this test exercises the
        // public path: write hooks.json into the *real* state directory under a
        // unique sentinel command, then verify the sentinel ran.
        let sentinelFile = tempDir.appendingPathComponent("hook-ran.txt")
        let sentinel = sentinelFile.path
        let command = "echo \"$LINEY_HOOK,$LINEY_APP_VERSION\" > \"\(sentinel)\""
        let settings = HookSettings(hooks: [.appOnQuit: [HookCommand(command: command)]])

        let persistence = HookSettingsPersistence()
        let originalContents = try? Data(contentsOf: persistence.fileURL)
        defer {
            if let originalContents {
                try? originalContents.write(to: persistence.fileURL, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: persistence.fileURL)
            }
            HookRunner.shared.invalidateCache()
        }
        try persistence.write(settings)
        HookRunner.shared.invalidateCache()
        HookRunner.shared.updateMasterSwitch(true)

        HookRunner.shared.fireBlocking(
            .appOnQuit,
            context: HookContext.app(appVersion: "1.2.3"),
            timeout: 5.0
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel), "hook command did not produce side effect file")
        let written = try String(contentsOfFile: sentinel, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(written, "app.on_quit,1.2.3")
    }

    func testFireDoesNothingWhenMasterSwitchOff() throws {
        let sentinel = tempDir.appendingPathComponent("should-not-run.txt").path
        let command = "touch \"\(sentinel)\""
        let settings = HookSettings(hooks: [.appOnLaunch: [HookCommand(command: command)]])

        let persistence = HookSettingsPersistence()
        let originalContents = try? Data(contentsOf: persistence.fileURL)
        defer {
            if let originalContents {
                try? originalContents.write(to: persistence.fileURL, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: persistence.fileURL)
            }
            HookRunner.shared.invalidateCache()
        }
        try persistence.write(settings)
        HookRunner.shared.invalidateCache()
        HookRunner.shared.updateMasterSwitch(false)

        HookRunner.shared.fire(.appOnLaunch, context: HookContext.app(appVersion: "0.0.0"))
        // Wait briefly to be sure no async work fired.
        Thread.sleep(forTimeInterval: 0.3)

        XCTAssertFalse(FileManager.default.fileExists(atPath: sentinel))
    }

    func testFireBlockingTimeoutTerminatesLongRunningHook() throws {
        let sentinel = tempDir.appendingPathComponent("late.txt").path
        // Sleep longer than timeout, then write the file. Timeout should fire
        // before the file is written.
        let command = "sleep 5; touch \"\(sentinel)\""
        let settings = HookSettings(hooks: [.appOnQuit: [HookCommand(command: command)]])

        let persistence = HookSettingsPersistence()
        let originalContents = try? Data(contentsOf: persistence.fileURL)
        defer {
            if let originalContents {
                try? originalContents.write(to: persistence.fileURL, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: persistence.fileURL)
            }
            HookRunner.shared.invalidateCache()
        }
        try persistence.write(settings)
        HookRunner.shared.invalidateCache()
        HookRunner.shared.updateMasterSwitch(true)

        let started = Date()
        HookRunner.shared.fireBlocking(
            .appOnQuit,
            context: HookContext.app(appVersion: "1.0"),
            timeout: 0.5
        )
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertLessThan(elapsed, 2.0, "fireBlocking did not honour timeout (elapsed: \(elapsed)s)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sentinel))
    }
}
