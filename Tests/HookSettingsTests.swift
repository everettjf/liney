//
//  HookSettingsTests.swift
//  LineyTests
//
//  Author: everettjf
//

import XCTest
@testable import Liney

final class HookSettingsTests: XCTestCase {
    func testEmptyHookSettingsHasAllKindsPresent() {
        let settings = HookSettings.empty
        for kind in HookKind.allCases {
            XCTAssertNotNil(settings.hooks[kind])
            XCTAssertEqual(settings.hooks[kind]?.count, 0)
        }
    }

    func testEnabledCommandsFiltersDisabledAndEmpty() {
        let settings = HookSettings(hooks: [
            .appOnLaunch: [
                HookCommand(enabled: true, command: "echo a"),
                HookCommand(enabled: false, command: "echo b"),
                HookCommand(enabled: true, command: "   ")
            ],
            .sessionOnStart: []
        ])
        let active = settings.enabledCommands(for: .appOnLaunch)
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.command, "echo a")
        XCTAssertEqual(settings.enabledCommands(for: .sessionOnStart), [])
    }

    func testRoundTripEncodingPreservesKindsAndCommands() throws {
        let original = HookSettings(hooks: [
            .appOnLaunch: [HookCommand(enabled: true, sync: true, command: "echo launch", timeoutSeconds: 3)],
            .appOnQuit: [],
            .sessionOnStart: [HookCommand(enabled: false, sync: false, command: "echo start")],
            .sessionOnExit: []
        ])

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(HookSettings.self, from: data)

        XCTAssertEqual(decoded.version, HookSettings.currentVersion)
        XCTAssertEqual(decoded.hooks[.appOnLaunch], original.hooks[.appOnLaunch])
        XCTAssertEqual(decoded.hooks[.appOnQuit], original.hooks[.appOnQuit])
        XCTAssertEqual(decoded.hooks[.sessionOnStart], original.hooks[.sessionOnStart])
        XCTAssertEqual(decoded.hooks[.sessionOnExit], original.hooks[.sessionOnExit])
        XCTAssertEqual(decoded.hooks[.appOnLaunch]?.first?.sync, true)
        XCTAssertEqual(decoded.hooks[.appOnLaunch]?.first?.timeoutSeconds, 3)
    }

    func testCommandDecodingDefaultsSyncToFalseAndTimeoutToNil() throws {
        let json = """
        {
          "version": 1,
          "hooks": {
            "app.on_launch": [{ "enabled": true, "command": "echo legacy" }]
          }
        }
        """
        let decoded = try JSONDecoder().decode(HookSettings.self, from: Data(json.utf8))
        let cmd = decoded.hooks[.appOnLaunch]?.first
        XCTAssertEqual(cmd?.command, "echo legacy")
        XCTAssertEqual(cmd?.sync, false)
        XCTAssertNil(cmd?.timeoutSeconds)
        XCTAssertEqual(cmd?.effectiveTimeout, HookCommand.defaultAsyncTimeout)
    }

    func testEffectiveTimeoutUsesPerModeDefaults() {
        let async = HookCommand(sync: false, command: "echo")
        let sync = HookCommand(sync: true, command: "echo")
        let overridden = HookCommand(sync: true, command: "echo", timeoutSeconds: 1.5)

        XCTAssertEqual(async.effectiveTimeout, HookCommand.defaultAsyncTimeout)
        XCTAssertEqual(sync.effectiveTimeout, HookCommand.defaultSyncTimeout)
        XCTAssertEqual(overridden.effectiveTimeout, 1.5)
    }

    func testDecodingIgnoresUnknownHookKinds() throws {
        let json = """
        {
          "version": 1,
          "hooks": {
            "app.on_launch": [{ "enabled": true, "command": "echo ok" }],
            "made.up.hook": [{ "enabled": true, "command": "wat" }]
          }
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(HookSettings.self, from: data)
        XCTAssertEqual(decoded.enabledCommands(for: .appOnLaunch).count, 1)
        XCTAssertEqual(decoded.enabledCommands(for: .appOnQuit).count, 0)
    }

    func testHookContextProducesEnvironmentForSessionHook() {
        let context = HookContext(
            appVersion: "1.2.3",
            sessionID: "abc",
            sessionCWD: "/tmp/x",
            sessionShell: "/bin/zsh",
            sessionBackend: "localShell",
            sessionExitCode: 7
        )
        let env = context.environmentVariables(for: .sessionOnExit)
        XCTAssertEqual(env["LINEY_HOOK"], "session.on_exit")
        XCTAssertEqual(env["LINEY_APP_VERSION"], "1.2.3")
        XCTAssertEqual(env["LINEY_SESSION_ID"], "abc")
        XCTAssertEqual(env["LINEY_SESSION_CWD"], "/tmp/x")
        XCTAssertEqual(env["LINEY_SESSION_SHELL"], "/bin/zsh")
        XCTAssertEqual(env["LINEY_SESSION_BACKEND"], "localShell")
        XCTAssertEqual(env["LINEY_SESSION_EXIT_CODE"], "7")
    }

    func testHookContextOmitsSessionFieldsForAppHook() {
        let context = HookContext.app(appVersion: "9.9.9")
        let env = context.environmentVariables(for: .appOnLaunch)
        XCTAssertEqual(env["LINEY_HOOK"], "app.on_launch")
        XCTAssertEqual(env["LINEY_APP_VERSION"], "9.9.9")
        XCTAssertNil(env["LINEY_SESSION_ID"])
        XCTAssertNil(env["LINEY_SESSION_CWD"])
        XCTAssertNil(env["LINEY_SESSION_EXIT_CODE"])
    }
}
