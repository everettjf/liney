//
//  QuickCommandSupportTests.swift
//  LineyTests
//
//  Author: everettjf
//

import Carbon
import XCTest
@testable import Liney

final class QuickCommandSupportTests: XCTestCase {
    func testLegacySettingsDecodeDefaultsQuickCommands() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))

        XCTAssertEqual(settings.quickCommandPresets, QuickCommandCatalog.defaultCommands)
        XCTAssertTrue(settings.quickCommandRecentIDs.isEmpty)
        XCTAssertFalse(settings.hotKeyWindowEnabled)
        XCTAssertEqual(
            settings.hotKeyWindowShortcut,
            StoredShortcut(key: " ", command: true, shift: true, option: false, control: false)
        )
        XCTAssertEqual(
            QuickCommandCatalog.defaultCommands.first(where: { $0.id == "codex-resume" })?.command,
            "codex resume"
        )
        XCTAssertEqual(
            LineyKeyboardShortcuts.effectiveShortcut(for: .closeWindow, in: settings),
            StoredShortcut(key: "w", command: true, shift: false, option: false, control: true)
        )
    }

    func testSettingsEncodingPreservesHotKeyWindowFields() throws {
        let settings = AppSettings(
            hotKeyWindowEnabled: true,
            hotKeyWindowShortcut: StoredShortcut(key: "k", command: true, shift: true, option: false, control: false)
        )

        let data = try JSONEncoder().encode(settings)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["hotKeyWindowEnabled"] as? Bool, true)

        let shortcut = try XCTUnwrap(object["hotKeyWindowShortcut"] as? [String: Any])
        XCTAssertEqual(shortcut["key"] as? String, "k")
        XCTAssertEqual(shortcut["command"] as? Bool, true)
        XCTAssertEqual(shortcut["shift"] as? Bool, true)
        XCTAssertEqual(shortcut["option"] as? Bool, false)
        XCTAssertEqual(shortcut["control"] as? Bool, false)
    }

    func testDebugBuildUsesSeparatePersistenceDirectoryName() {
        XCTAssertEqual(lineyStateDirectoryName(isDebugBuild: true), ".liney-debug")
        XCTAssertEqual(lineyStateDirectoryName(isDebugBuild: false), ".liney")
    }

    func testQuickCommandNormalizationTrimsAndDropsDuplicates() {
        let commands = [
            QuickCommandPreset(
                id: "dup",
                title: "  ",
                command: "  ls -la  ",
                category: .linux
            ),
            QuickCommandPreset(
                id: "dup",
                title: "Other",
                command: "pwd",
                category: .linux
            ),
            QuickCommandPreset(
                id: "empty",
                title: "Empty",
                command: "   ",
                category: .codex
            ),
        ]

        let normalized = QuickCommandCatalog.normalizedCommands(commands)

        XCTAssertEqual(normalized.count, 1)
        XCTAssertEqual(normalized[0].id, "dup")
        XCTAssertEqual(normalized[0].title, "ls -la")
        XCTAssertEqual(normalized[0].command, "ls -la")
    }

    func testRecentQuickCommandsArePrunedAndDeduplicated() {
        let commands = [
            QuickCommandPreset(id: "a", title: "A", command: "a", category: .codex),
            QuickCommandPreset(id: "b", title: "B", command: "b", category: .cloud),
        ]

        let normalized = QuickCommandCatalog.normalizedRecentCommandIDs(
            ["missing", "a", "a", "b", "c"],
            availableCommands: commands
        )

        XCTAssertEqual(normalized, ["a", "b"])
    }

    func testShortcutAssignmentDisablesConflictingAction() {
        var settings = AppSettings()
        let shortcut = StoredShortcut(key: "p", command: true, shift: false, option: false, control: false)

        LineyKeyboardShortcuts.setShortcut(shortcut, for: .openDiff, in: &settings)

        XCTAssertEqual(LineyKeyboardShortcuts.effectiveShortcut(for: .openDiff, in: settings), shortcut)
        XCTAssertNil(LineyKeyboardShortcuts.effectiveShortcut(for: .toggleCommandPalette, in: settings))
        XCTAssertEqual(LineyKeyboardShortcuts.state(for: .toggleCommandPalette, in: settings), .disabled)
    }

    func testShortcutResetRestoresDefaultBinding() {
        var settings = AppSettings()

        LineyKeyboardShortcuts.disableShortcut(for: .closePane, in: &settings)
        XCTAssertNil(LineyKeyboardShortcuts.effectiveShortcut(for: .closePane, in: settings))

        LineyKeyboardShortcuts.resetShortcut(for: .closePane, in: &settings)

        XCTAssertEqual(
            LineyKeyboardShortcuts.effectiveShortcut(for: .closePane, in: settings),
            StoredShortcut(key: "w", command: true, shift: true, option: false, control: false)
        )
    }

    func testNumberedTabShortcutNormalizesToDigitTemplate() {
        var settings = AppSettings()
        let shortcut = StoredShortcut(key: "7", command: true, shift: false, option: false, control: false)

        LineyKeyboardShortcuts.setShortcut(shortcut, for: .selectTabByNumber, in: &settings)

        XCTAssertEqual(
            LineyKeyboardShortcuts.effectiveShortcut(for: .selectTabByNumber, in: settings),
            StoredShortcut(key: "1", command: true, shift: false, option: false, control: false)
        )
        XCTAssertEqual(
            LineyKeyboardShortcuts.displayString(for: .selectTabByNumber, in: settings),
            "⌘1…9"
        )
    }

    func testStoredShortcutComputesCarbonHotKeyValues() {
        let shortcut = StoredShortcut(key: " ", command: false, shift: true, option: true, control: false)

        XCTAssertEqual(shortcut.carbonKeyCode, UInt32(kVK_Space))
        XCTAssertEqual(shortcut.carbonModifierFlags, UInt32(optionKey | shiftKey))
    }

    func testHotKeyWindowKeepsAppRunningWhenLastWindowCloses() {
        XCTAssertFalse(lineyShouldTerminateAfterLastWindowClosed(hotKeyWindowEnabled: true))
    }

    func testStandardWindowModeTerminatesAfterLastWindowCloses() {
        XCTAssertTrue(lineyShouldTerminateAfterLastWindowClosed(hotKeyWindowEnabled: false))
    }

    func testDockReopenRestoresWindowWhenNoVisibleWindows() {
        XCTAssertTrue(lineyShouldReopenMainWindow(hasVisibleWindows: false))
        XCTAssertFalse(lineyShouldReopenMainWindow(hasVisibleWindows: true))
    }
}
