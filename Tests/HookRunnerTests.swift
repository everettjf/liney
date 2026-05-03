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

    func testFireWithSyncCommandBlocksUntilDone() throws {
        let sentinel = tempDir.appendingPathComponent("sync-sentinel.txt").path
        let command = "echo \"$LINEY_HOOK\" > \"\(sentinel)\""
        let settings = HookSettings(hooks: [
            .sessionOnStart: [HookCommand(enabled: true, sync: true, command: command, timeoutSeconds: 5)]
        ])

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

        // Sync semantic: by the time fire() returns, the side effect must be
        // visible — no sleep / polling required.
        HookRunner.shared.fire(.sessionOnStart, context: HookContext.app(appVersion: "1.0"))

        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel))
        let written = try String(contentsOfFile: sentinel, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(written, "session.on_start")
    }

    func testFireWithAsyncCommandReturnsBeforeSideEffect() throws {
        let sentinel = tempDir.appendingPathComponent("async-sentinel.txt").path
        // Sleep enough that we can observe "fire returned without the file".
        let command = "sleep 0.5; touch \"\(sentinel)\""
        let settings = HookSettings(hooks: [
            .sessionOnStart: [HookCommand(enabled: true, sync: false, command: command)]
        ])

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
        HookRunner.shared.fire(.sessionOnStart, context: HookContext.app(appVersion: "1.0"))
        let returnElapsed = Date().timeIntervalSince(started)
        XCTAssertLessThan(returnElapsed, 0.3, "fire() with async command should not block")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sentinel))

        // Wait for the async work to complete and check the side effect lands.
        var attempts = 0
        while attempts < 60, !FileManager.default.fileExists(atPath: sentinel) {
            Thread.sleep(forTimeInterval: 0.05)
            attempts += 1
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel), "async side effect did not land within 3s")
    }

    func testFireRunsExternalScriptFile() throws {
        let scriptDir = tempDir.appendingPathComponent("scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scriptDir, withIntermediateDirectories: true)
        let scriptURL = scriptDir.appendingPathComponent("hello.sh", isDirectory: false)
        let sentinelFile = tempDir.appendingPathComponent("script-sentinel.txt").path
        let scriptBody = """
        #!/bin/sh
        echo "$LINEY_HOOK from script" > "\(sentinelFile)"
        """
        try scriptBody.write(to: scriptURL, atomically: true, encoding: .utf8)

        let settings = HookSettings(hooks: [
            .sessionOnStart: [HookCommand(enabled: true, sync: true, script: scriptURL.path, timeoutSeconds: 5)]
        ])

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

        HookRunner.shared.fire(.sessionOnStart, context: HookContext.app(appVersion: "1.0"))

        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinelFile), "script file did not run")
        let written = try String(contentsOfFile: sentinelFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(written, "session.on_start from script")
    }

    func testFireLogsScriptNotFoundError() throws {
        let missingPath = tempDir.appendingPathComponent("does-not-exist.sh").path
        let settings = HookSettings(hooks: [
            .sessionOnStart: [HookCommand(enabled: true, sync: true, script: missingPath, timeoutSeconds: 5)]
        ])

        let persistence = HookSettingsPersistence()
        let originalContents = try? Data(contentsOf: persistence.fileURL)
        let originalLog = try? Data(contentsOf: persistence.logFileURL)
        defer {
            if let originalContents {
                try? originalContents.write(to: persistence.fileURL, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: persistence.fileURL)
            }
            if let originalLog {
                try? originalLog.write(to: persistence.logFileURL, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: persistence.logFileURL)
            }
            HookRunner.shared.invalidateCache()
        }
        try persistence.write(settings)
        HookRunner.shared.invalidateCache()
        HookRunner.shared.updateMasterSwitch(true)

        HookRunner.shared.fire(.sessionOnStart, context: HookContext.app(appVersion: "1.0"))

        // Logger writes async, so wait briefly for the line to land.
        var attempts = 0
        var logContents = ""
        while attempts < 50 {
            if let data = try? Data(contentsOf: persistence.logFileURL) {
                logContents = String(decoding: data, as: UTF8.self)
                if logContents.contains("script not found") { break }
            }
            Thread.sleep(forTimeInterval: 0.05)
            attempts += 1
        }
        XCTAssertTrue(logContents.contains("script not found"), "expected script-not-found error in log; got: \(logContents)")
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
