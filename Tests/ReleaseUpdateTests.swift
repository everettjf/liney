//
//  ReleaseUpdateTests.swift
//  LineyTests
//
//  Author: everettjf
//

import XCTest
@testable import Liney

final class ReleaseUpdateTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        LocalizationManager.shared.updateSelectedLanguage(.english)
    }

    override func tearDown() async throws {
        LocalizationManager.shared.updateSelectedLanguage(.automatic)
        try await super.tearDown()
    }
    
    func testNewWindowShortcutDefaultsToCommandN() {
        XCTAssertEqual(LineyShortcutAction.newWindow.category, .window)
        XCTAssertEqual(LineyShortcutAction.newWindow.title, "New Window")
        XCTAssertEqual(
            LineyShortcutAction.newWindow.defaultShortcut,
            StoredShortcut(key: "n", command: true, shift: false, option: false, control: false)
        )
    }

    func testWindowLifecycleHelpersRespectHotKeyAndVisibility() {
        XCTAssertTrue(lineyShouldTerminateAfterLastWindowClosed(hotKeyWindowEnabled: false, isRunningTests: false))
        XCTAssertFalse(lineyShouldTerminateAfterLastWindowClosed(hotKeyWindowEnabled: true, isRunningTests: false))
        XCTAssertTrue(lineyShouldReopenMainWindow(hasVisibleWindows: false))
        XCTAssertFalse(lineyShouldReopenMainWindow(hasVisibleWindows: true))
    }

    func testAppUpdaterDefaultsToStableAppcastFeed() {
        XCTAssertEqual(
            AppUpdaterController.defaultFeedURLString,
            "https://raw.githubusercontent.com/everettjf/liney/stable/appcast.xml"
        )
    }

    func testAppUpdaterFallsBackToStableFeedWhenInfoPlistValueMissing() {
        XCTAssertEqual(
            AppUpdaterController.resolveFeedURLString(infoDictionary: nil),
            AppUpdaterController.defaultFeedURLString
        )
        XCTAssertEqual(
            AppUpdaterController.resolveFeedURLString(infoDictionary: [:]),
            AppUpdaterController.defaultFeedURLString
        )
    }

    func testAppUpdaterPrefersInfoPlistFeedURL() {
        XCTAssertEqual(
            AppUpdaterController.resolveFeedURLString(
                infoDictionary: [AppUpdaterController.feedURLInfoPlistKey: "https://example.com/appcast.xml"]
            ),
            "https://example.com/appcast.xml"
        )
    }

    func testAppSettingsDecodesLegacyPayloadWithUpdateDefaults() throws {
        let data = Data(
            """
            {
              "autoRefreshEnabled": false,
              "autoRefreshIntervalSeconds": 60,
              "fileWatcherEnabled": false,
              "githubIntegrationEnabled": true,
              "systemNotificationsEnabled": false,
              "showArchivedWorkspaces": true,
              "commandPaletteRecents": {
                "office": 123
              }
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertFalse(decoded.autoRefreshEnabled)
        XCTAssertEqual(decoded.autoRefreshIntervalSeconds, 60)
        XCTAssertTrue(decoded.autoClosePaneOnProcessExit)
        XCTAssertTrue(decoded.confirmQuitWhenCommandsRunning)
        XCTAssertTrue(decoded.autoCheckForUpdates)
        XCTAssertFalse(decoded.autoDownloadUpdates)
        XCTAssertTrue(decoded.sidebarShowsSecondaryLabels)
        XCTAssertTrue(decoded.sidebarShowsWorkspaceBadges)
        XCTAssertTrue(decoded.sidebarShowsWorktreeBadges)
        XCTAssertNil(decoded.terminalFontFamily)
        XCTAssertNil(decoded.terminalFontSize)
        XCTAssertEqual(decoded.defaultRepositoryIcon, .repositoryDefault)
        XCTAssertEqual(decoded.defaultLocalTerminalIcon, .localTerminalDefault)
        XCTAssertEqual(decoded.defaultWorktreeIcon, .worktreeDefault)
        XCTAssertEqual(decoded.releaseChannel, .stable)
        XCTAssertEqual(decoded.agentPresets.first?.name, "Claude Code")
        XCTAssertEqual(decoded.preferredAgentPresetID, AgentPreset.claudeCode.id)
        XCTAssertEqual(decoded.sshPresets.first?.name, "Shell")
        XCTAssertNil(decoded.preferredSSHPresetID)
    }

    func testAppSettingsPreservesEmptySSHPresets() throws {
        let encoded = try JSONEncoder().encode(
            AppSettings(
                sshPresets: [],
                preferredSSHPresetID: nil
            )
        )

        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)

        XCTAssertTrue(decoded.sshPresets.isEmpty)
        XCTAssertNil(decoded.preferredSSHPresetID)
    }

    func testAppSettingsPreservesCustomTerminalFontSize() throws {
        let encoded = try JSONEncoder().encode(
            AppSettings(terminalFontSize: 15)
        )

        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)
        XCTAssertEqual(decoded.terminalFontSize, 15)
    }

    func testAppSettingsPreservesCustomTerminalFontFamily() throws {
        let encoded = try JSONEncoder().encode(
            AppSettings(terminalFontFamily: "JetBrains Mono")
        )

        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)
        XCTAssertEqual(decoded.terminalFontFamily, "JetBrains Mono")
    }
}
