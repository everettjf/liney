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
        XCTAssertEqual(settings.quickCommandCategories, QuickCommandCatalog.defaultCategories)
        XCTAssertTrue(settings.quickCommandRecentIDs.isEmpty)
        XCTAssertFalse(settings.hotKeyWindowEnabled)
        XCTAssertTrue(settings.confirmQuitWhenCommandsRunning)
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
            StoredShortcut(key: "w", command: true, shift: true, option: false, control: false)
        )
    }

    func testLegacySettingsDecodeDefaultsAppLanguageToAutomatic() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))

        XCTAssertEqual(settings.appLanguage, .automatic)
    }

    func testSettingsEncodingPreservesAppLanguage() throws {
        let settings = AppSettings(appLanguage: .simplifiedChinese)

        let data = try JSONEncoder().encode(settings)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["appLanguage"] as? String, "simplifiedChinese")
    }

    func testSettingsEncodingPreservesHotKeyWindowFields() throws {
        let settings = AppSettings(
            confirmQuitWhenCommandsRunning: false,
            hotKeyWindowEnabled: true,
            hotKeyWindowShortcut: StoredShortcut(key: "k", command: true, shift: true, option: false, control: false)
        )

        let data = try JSONEncoder().encode(settings)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["hotKeyWindowEnabled"] as? Bool, true)
        XCTAssertEqual(object["confirmQuitWhenCommandsRunning"] as? Bool, false)

        let shortcut = try XCTUnwrap(object["hotKeyWindowShortcut"] as? [String: Any])
        XCTAssertEqual(shortcut["key"] as? String, "k")
        XCTAssertEqual(shortcut["command"] as? Bool, true)
        XCTAssertEqual(shortcut["shift"] as? Bool, true)
        XCTAssertEqual(shortcut["option"] as? Bool, false)
        XCTAssertEqual(shortcut["control"] as? Bool, false)
    }

    func testSettingsEncodeAndDecodePreserveUIScale() throws {
        let settings = AppSettings(uiScale: 1.25)

        let data = try JSONEncoder().encode(settings)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["uiScale"] as? Double, 1.25)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.uiScale, 1.25, accuracy: 0.001)
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
                categoryID: QuickCommandCategory.linux.id
            ),
            QuickCommandPreset(
                id: "dup",
                title: "Other",
                command: "pwd",
                categoryID: QuickCommandCategory.linux.id
            ),
            QuickCommandPreset(
                id: "empty",
                title: "Empty",
                command: "   ",
                categoryID: QuickCommandCategory.codex.id
            ),
        ]

        let normalized = QuickCommandCatalog.normalizedCommands(commands)

        XCTAssertEqual(normalized.count, 1)
        XCTAssertEqual(normalized[0].id, "dup")
        XCTAssertEqual(normalized[0].title, "ls -la")
        XCTAssertEqual(normalized[0].command, "ls -la")
    }

    func testQuickCommandNormalizationClearsConflictingShortcuts() {
        let reservedShortcut = StoredShortcut(key: "p", command: true, shift: false, option: false, control: false)
        let commands = [
            QuickCommandPreset(
                id: "first",
                title: "First",
                command: "echo first",
                categoryID: QuickCommandCategory.linux.id,
                shortcut: reservedShortcut
            ),
            QuickCommandPreset(
                id: "second",
                title: "Second",
                command: "echo second",
                categoryID: QuickCommandCategory.linux.id,
                shortcut: StoredShortcut(key: "k", command: true, shift: false, option: false, control: false)
            ),
            QuickCommandPreset(
                id: "third",
                title: "Third",
                command: "echo third",
                categoryID: QuickCommandCategory.linux.id,
                shortcut: StoredShortcut(key: "k", command: true, shift: false, option: false, control: false)
            ),
        ]

        let normalized = QuickCommandCatalog.normalizedCommands(commands, reservedShortcuts: Set([reservedShortcut]))

        XCTAssertNil(normalized[0].shortcut)
        XCTAssertEqual(normalized[1].shortcut, StoredShortcut(key: "k", command: true, shift: false, option: false, control: false))
        XCTAssertNil(normalized[2].shortcut)
    }

    func testQuickCommandShortcutMatchReturnsPreset() {
        let shortcut = StoredShortcut(key: "k", command: true, shift: true, option: false, control: false)
        let settings = AppSettings(
            quickCommandPresets: [
                QuickCommandPreset(
                    id: "deploy",
                    title: "Deploy",
                    command: "deploy-now",
                    categoryID: QuickCommandCategory.cloud.id,
                    shortcut: shortcut,
                    submitsReturn: true
                )
            ]
        )

        let event = try! XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command, .shift],
                timestamp: 1,
                windowNumber: 0,
                context: nil,
                characters: "K",
                charactersIgnoringModifiers: "k",
                isARepeat: false,
                keyCode: UInt16(kVK_ANSI_K)
            )
        )

        let match = lineyQuickCommandMatch(for: event, in: settings)
        XCTAssertEqual(match?.id, "deploy")
        XCTAssertEqual(match?.submitsReturn, true)
    }

    func testQuickCommandDispatchUsesRunOnlyWhenAutoReturnIsEnabled() {
        let insertPreset = QuickCommandPreset(
            id: "insert",
            title: "Insert",
            command: "codex",
            categoryID: QuickCommandCategory.codex.id,
            submitsReturn: false
        )
        let runPreset = QuickCommandPreset(
            id: "run",
            title: "Run",
            command: "codex",
            categoryID: QuickCommandCategory.codex.id,
            submitsReturn: true
        )

        XCTAssertEqual(lineyQuickCommandDispatch(for: insertPreset), .insert("codex"))
        XCTAssertEqual(lineyQuickCommandDispatch(for: runPreset), .run("codex"))
    }

    func testSettingsEncodingPreservesQuickCommandShortcutAndAutoReturn() throws {
        let settings = AppSettings(
            quickCommandPresets: [
                QuickCommandPreset(
                    id: "run-tests",
                    title: "Run Tests",
                    command: "swift test",
                    categoryID: QuickCommandCategory.codex.id,
                    shortcut: StoredShortcut(key: "t", command: true, shift: true, option: false, control: false),
                    submitsReturn: true
                )
            ]
        )

        let data = try JSONEncoder().encode(settings)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let presets = try XCTUnwrap(object["quickCommandPresets"] as? [[String: Any]])
        let shortcut = try XCTUnwrap(presets.first?["shortcut"] as? [String: Any])

        XCTAssertEqual(shortcut["key"] as? String, "t")
        XCTAssertEqual(shortcut["command"] as? Bool, true)
        XCTAssertEqual(shortcut["shift"] as? Bool, true)
        XCTAssertEqual(presets.first?["submitsReturn"] as? Bool, true)
    }

    func testRecentQuickCommandsArePrunedAndDeduplicated() {
        let commands = [
            QuickCommandPreset(id: "a", title: "A", command: "a", categoryID: QuickCommandCategory.codex.id),
            QuickCommandPreset(id: "b", title: "B", command: "b", categoryID: QuickCommandCategory.cloud.id),
        ]

        let normalized = QuickCommandCatalog.normalizedRecentCommandIDs(
            ["missing", "a", "a", "b", "c"],
            availableCommands: commands
        )

        XCTAssertEqual(normalized, ["a", "b"])
    }

    func testQuickCommandPresetDecodesLegacyCategoryString() throws {
        let preset = try JSONDecoder().decode(
            QuickCommandPreset.self,
            from: Data(#"{"id":"legacy","title":"Legacy","command":"ls","category":"linux"}"#.utf8)
        )

        XCTAssertEqual(preset.categoryID, QuickCommandCategory.linux.id)
    }

    func testQuickCommandCategoryDecodesLegacyStringValue() throws {
        let category = try JSONDecoder().decode(
            QuickCommandCategory.self,
            from: Data(#""cloud""#.utf8)
        )

        XCTAssertEqual(category, .cloud)
    }

    func testQuickCommandCategoriesNormalizeByKeepingBuiltInsAndCustomCategories() {
        let custom = QuickCommandCategory(id: "custom-tools", title: "Tools", symbolName: "tag")

        let normalized = QuickCommandCatalog.normalizedCategories([custom, .linux])

        XCTAssertTrue(normalized.contains(.linux))
        XCTAssertTrue(normalized.contains(custom))
        XCTAssertEqual(normalized.first, .general)
    }

    func testQuickCommandNormalizationFallsBackWhenCategoryIsMissing() {
        let normalized = QuickCommandCatalog.normalizedCommands(
            [
                QuickCommandPreset(
                    id: "custom",
                    title: "Custom",
                    command: "echo hi",
                    categoryID: "missing"
                )
            ],
            categories: QuickCommandCatalog.defaultCategories
        )

        XCTAssertEqual(normalized.first?.categoryID, QuickCommandCategory.general.id)
    }

    func testReplacingQuickCommandClearsConflictingShortcutFromPreviousCommand() {
        let shortcut = StoredShortcut(key: "k", command: true, shift: true, option: false, control: false)
        let codex = QuickCommandPreset(
            id: "codex",
            title: "Codex",
            command: "codex",
            categoryID: QuickCommandCategory.codex.id,
            shortcut: shortcut
        )
        let claude = QuickCommandPreset(
            id: "claude",
            title: "Claude",
            command: "claude",
            categoryID: QuickCommandCategory.claude.id
        )

        var updatedClaude = claude
        updatedClaude.shortcut = shortcut

        let replaced = QuickCommandCatalog.replacingCommand(updatedClaude, in: [codex, claude])

        XCTAssertNil(replaced.first(where: { $0.id == "codex" })?.shortcut)
        XCTAssertEqual(replaced.first(where: { $0.id == "claude" })?.shortcut, shortcut)
    }

    func testPredefinedQuickCommandLibraryContainsLargeCuratedCatalog() {
        XCTAssertEqual(QuickCommandCatalog.predefinedCommands.count, 200)
        XCTAssertEqual(QuickCommandCatalog.predefinedCommandCount, QuickCommandCatalog.predefinedCommands.count)
        XCTAssertTrue(QuickCommandCatalog.defaultCategories.contains(.complex))

        let complexCommands = QuickCommandCatalog.predefinedCommands.filter {
            $0.categoryID == QuickCommandCategory.complex.id
        }
        XCTAssertGreaterThanOrEqual(complexCommands.count, 70)
    }

    func testRecommendedComplexSubsetResolvesToExistingComplexCommands() throws {
        let allCommandsByID = Dictionary(uniqueKeysWithValues: QuickCommandCatalog.predefinedCommands.map { ($0.id, $0) })

        XCTAssertEqual(QuickCommandCatalog.recommendedComplexCommandIDs.count, 12)

        for id in QuickCommandCatalog.recommendedComplexCommandIDs {
            let command = try XCTUnwrap(allCommandsByID[id])
            XCTAssertEqual(command.categoryID, QuickCommandCategory.complex.id)
        }
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
            StoredShortcut(key: "w", command: true, shift: false, option: true, control: false)
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

    func testPaneFocusShortcutsDefaultToCommandOptionArrows() {
        let settings = AppSettings()

        XCTAssertEqual(
            LineyKeyboardShortcuts.effectiveShortcut(for: .focusPaneLeft, in: settings),
            StoredShortcut(key: "←", command: true, shift: false, option: true, control: false)
        )
        XCTAssertEqual(
            LineyKeyboardShortcuts.effectiveShortcut(for: .focusPaneRight, in: settings),
            StoredShortcut(key: "→", command: true, shift: false, option: true, control: false)
        )
        XCTAssertEqual(
            LineyKeyboardShortcuts.effectiveShortcut(for: .focusPaneUp, in: settings),
            StoredShortcut(key: "↑", command: true, shift: false, option: true, control: false)
        )
        XCTAssertEqual(
            LineyKeyboardShortcuts.effectiveShortcut(for: .focusPaneDown, in: settings),
            StoredShortcut(key: "↓", command: true, shift: false, option: true, control: false)
        )
    }

    func testTabNavigationShortcutsUseControlTabVariants() {
        let settings = AppSettings()

        XCTAssertEqual(
            LineyKeyboardShortcuts.effectiveShortcut(for: .nextTab, in: settings),
            StoredShortcut(key: "\t", command: false, shift: false, option: false, control: true)
        )
        XCTAssertEqual(
            LineyKeyboardShortcuts.effectiveShortcut(for: .previousTab, in: settings),
            StoredShortcut(key: "\t", command: false, shift: true, option: false, control: true)
        )
    }

    func testPaneAndDiffShortcutsUseNewDefaults() {
        let settings = AppSettings()

        XCTAssertEqual(
            LineyKeyboardShortcuts.effectiveShortcut(for: .duplicatePane, in: settings),
            StoredShortcut(key: "d", command: true, shift: false, option: true, control: false)
        )
        XCTAssertEqual(
            LineyKeyboardShortcuts.effectiveShortcut(for: .togglePaneZoom, in: settings),
            StoredShortcut(key: "\r", command: true, shift: false, option: false, control: false)
        )
        XCTAssertEqual(
            LineyKeyboardShortcuts.effectiveShortcut(for: .openDiff, in: settings),
            StoredShortcut(key: ".", command: true, shift: true, option: false, control: false)
        )
    }

    func testStandardMenuShortcutsUseConfigurableDefaults() {
        let settings = AppSettings()

        XCTAssertEqual(
            LineyKeyboardShortcuts.effectiveShortcut(for: .hideApp, in: settings),
            StoredShortcut(key: "h", command: true, shift: false, option: false, control: false)
        )
        XCTAssertEqual(
            LineyKeyboardShortcuts.effectiveShortcut(for: .hideOtherApps, in: settings),
            StoredShortcut(key: "h", command: true, shift: false, option: true, control: false)
        )
        XCTAssertEqual(
            LineyKeyboardShortcuts.effectiveShortcut(for: .quitApp, in: settings),
            StoredShortcut(key: "q", command: true, shift: false, option: false, control: false)
        )
        XCTAssertEqual(
            LineyKeyboardShortcuts.effectiveShortcut(for: .copy, in: settings),
            StoredShortcut(key: "c", command: true, shift: false, option: false, control: false)
        )
        XCTAssertEqual(
            LineyKeyboardShortcuts.effectiveShortcut(for: .findPrevious, in: settings),
            StoredShortcut(key: "g", command: true, shift: true, option: false, control: false)
        )
        XCTAssertEqual(
            LineyKeyboardShortcuts.effectiveShortcut(for: .minimizeWindow, in: settings),
            StoredShortcut(key: "m", command: true, shift: false, option: false, control: false)
        )
    }

    func testShortcutMatchingSupportsArrowKeys() {
        let settings = AppSettings()

        let event = try! XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command, .option],
                timestamp: 1,
                windowNumber: 0,
                context: nil,
                characters: "\u{F702}",
                charactersIgnoringModifiers: "\u{F702}",
                isARepeat: false,
                keyCode: UInt16(kVK_LeftArrow)
            )
        )

        XCTAssertEqual(
            lineyShortcutMatch(for: event, in: settings),
            LineyShortcutMatch(action: .focusPaneLeft, tabNumber: nil)
        )
    }

    func testShortcutMatchingUsesStoredKeyForOptionModifiedLetters() {
        var settings = AppSettings()
        let shortcut = StoredShortcut(key: "d", command: false, shift: false, option: true, control: false)
        LineyKeyboardShortcuts.setShortcut(shortcut, for: .splitRight, in: &settings)

        let event = try! XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.option],
                timestamp: 1,
                windowNumber: 0,
                context: nil,
                characters: "\u{2202}",
                charactersIgnoringModifiers: "d",
                isARepeat: false,
                keyCode: UInt16(kVK_ANSI_D)
            )
        )

        XCTAssertEqual(
            lineyShortcutMatch(for: event, in: settings),
            LineyShortcutMatch(action: .splitRight, tabNumber: nil)
        )
    }

    func testShortcutMatchingSupportsControlTab() {
        let settings = AppSettings()

        let event = try! XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.control],
                timestamp: 1,
                windowNumber: 0,
                context: nil,
                characters: "\t",
                charactersIgnoringModifiers: "\t",
                isARepeat: false,
                keyCode: UInt16(kVK_Tab)
            )
        )

        XCTAssertEqual(
            lineyShortcutMatch(for: event, in: settings),
            LineyShortcutMatch(action: .nextTab, tabNumber: nil)
        )
    }

    func testShortcutMatchingSupportsCommandReturn() {
        let settings = AppSettings()

        let event = try! XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command],
                timestamp: 1,
                windowNumber: 0,
                context: nil,
                characters: "\r",
                charactersIgnoringModifiers: "\r",
                isARepeat: false,
                keyCode: UInt16(kVK_Return)
            )
        )

        XCTAssertEqual(
            lineyShortcutMatch(for: event, in: settings),
            LineyShortcutMatch(action: .togglePaneZoom, tabNumber: nil)
        )
    }

    func testHotKeyWindowKeepsAppRunningWhenLastWindowCloses() {
        XCTAssertFalse(lineyShouldTerminateAfterLastWindowClosed(hotKeyWindowEnabled: true, isRunningTests: false))
    }

    func testStandardWindowModeTerminatesAfterLastWindowCloses() {
        XCTAssertTrue(lineyShouldTerminateAfterLastWindowClosed(hotKeyWindowEnabled: false, isRunningTests: false))
    }

    func testRunningTestsKeepsAppAliveAfterLastWindowCloses() {
        XCTAssertFalse(lineyShouldTerminateAfterLastWindowClosed(hotKeyWindowEnabled: false, isRunningTests: true))
    }

    func testLastWindowCloseInterceptsTerminationWhenQuitNeedsConfirmation() {
        XCTAssertTrue(
            lineyShouldInterceptLastWindowCloseForTermination(
                hotKeyWindowEnabled: false,
                openWindowCount: 1,
                needsConfirmQuit: true
            )
        )
        XCTAssertFalse(
            lineyShouldInterceptLastWindowCloseForTermination(
                hotKeyWindowEnabled: false,
                openWindowCount: 2,
                needsConfirmQuit: true
            )
        )
        XCTAssertFalse(
            lineyShouldInterceptLastWindowCloseForTermination(
                hotKeyWindowEnabled: true,
                openWindowCount: 1,
                needsConfirmQuit: true
            )
        )
        XCTAssertFalse(
            lineyShouldInterceptLastWindowCloseForTermination(
                hotKeyWindowEnabled: false,
                openWindowCount: 1,
                needsConfirmQuit: false
            )
        )
    }

    func testDockReopenRestoresWindowWhenNoVisibleWindows() {
        XCTAssertTrue(lineyShouldReopenMainWindow(hasVisibleWindows: false))
        XCTAssertFalse(lineyShouldReopenMainWindow(hasVisibleWindows: true))
    }

    func testQuitConfirmationOnlyAppliesWhenEnabledAndCommandsNeedIt() {
        XCTAssertTrue(
            lineyShouldConfirmTermination(
                confirmQuitWhenCommandsRunning: true,
                needsConfirmQuit: true
            )
        )
        XCTAssertFalse(
            lineyShouldConfirmTermination(
                confirmQuitWhenCommandsRunning: false,
                needsConfirmQuit: true
            )
        )
        XCTAssertFalse(
            lineyShouldConfirmTermination(
                confirmQuitWhenCommandsRunning: true,
                needsConfirmQuit: false
            )
        )
    }

    func testQuitConfirmationCopyUsesSingularAndPluralText() {
        LocalizationManager.shared.updateSelectedLanguage(.english)
        XCTAssertEqual(
            lineyQuitConfirmationCopy(quitConfirmationSessionCount: 1).message,
            "1 terminal session still has a running command. Quitting now will stop it. You can turn this confirmation off in Settings > General."
        )
        XCTAssertEqual(
            lineyQuitConfirmationCopy(quitConfirmationSessionCount: 3).message,
            "3 terminal sessions still have running commands. Quitting now will stop them. You can turn this confirmation off in Settings > General."
        )

        LocalizationManager.shared.updateSelectedLanguage(.simplifiedChinese)
        XCTAssertEqual(
            lineyQuitConfirmationCopy(quitConfirmationSessionCount: 1).title,
            "要退出 Liney 吗？"
        )
        XCTAssertEqual(
            lineyQuitConfirmationCopy(quitConfirmationSessionCount: 1).message,
            "仍有 1 个终端会话在运行命令。 现在退出会停止它。 你可以在“设置 > 通用”中关闭此确认。"
        )
        XCTAssertEqual(
            lineyQuitConfirmationCopy(quitConfirmationSessionCount: 3).message,
            "仍有 3 个终端会话在运行命令。 现在退出会停止它们。 你可以在“设置 > 通用”中关闭此确认。"
        )

        LocalizationManager.shared.updateSelectedLanguage(.automatic)
    }

    func testGhosttyLogFilterSuppressesKnownGhosttySpamOnly() {
        XCTAssertTrue(LineyGhosttyLogFilter.shouldSuppress("io_thread: mailbox message=start_synchronized_output"))
        XCTAssertTrue(LineyGhosttyLogFilter.shouldSuppress("debug(io_thread): mailbox message=start_synchronized_output"))
        XCTAssertTrue(LineyGhosttyLogFilter.shouldSuppress("reading configuration file path=/Users/eevv/Library/Application Support/com.mitchellh.ghostty/config"))
        XCTAssertTrue(LineyGhosttyLogFilter.shouldSuppress("config: default shell source=env value=/bin/zsh"))
        XCTAssertTrue(LineyGhosttyLogFilter.shouldSuppress("generic_renderer: updating display link display id=3"))
        XCTAssertTrue(LineyGhosttyLogFilter.shouldSuppress("\n"))
        XCTAssertTrue(LineyGhosttyLogFilter.shouldSuppress("   \n"))
        XCTAssertFalse(LineyGhosttyLogFilter.shouldSuppress("io_thread: mailbox message=end_synchronized_output"))
        XCTAssertFalse(LineyGhosttyLogFilter.shouldSuppress("warning(io_thread): error draining mailbox err=something"))
        XCTAssertFalse(LineyGhosttyLogFilter.shouldSuppress("generic_renderer: fatal display link failure"))
    }
}
