//
//  ReleaseUpdateTests.swift
//  LineyTests
//
//  Author: everettjf
//

import XCTest
@testable import Liney

final class ReleaseUpdateTests: XCTestCase {
    func testNewWindowShortcutDefaultsToCommandN() {
        XCTAssertEqual(LineyShortcutAction.newWindow.category, .window)
        XCTAssertEqual(LineyShortcutAction.newWindow.title, "New Window")
        XCTAssertEqual(
            LineyShortcutAction.newWindow.defaultShortcut,
            StoredShortcut(key: "n", command: true, shift: false, option: false, control: false)
        )
    }

    func testWindowLifecycleHelpersRespectHotKeyAndVisibility() {
        XCTAssertTrue(lineyShouldTerminateAfterLastWindowClosed(hotKeyWindowEnabled: false))
        XCTAssertFalse(lineyShouldTerminateAfterLastWindowClosed(hotKeyWindowEnabled: true))
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
        XCTAssertEqual(decoded.defaultRepositoryIcon, .repositoryDefault)
        XCTAssertEqual(decoded.defaultLocalTerminalIcon, .localTerminalDefault)
        XCTAssertEqual(decoded.defaultWorktreeIcon, .worktreeDefault)
        XCTAssertEqual(decoded.releaseChannel, .stable)
    }
}
