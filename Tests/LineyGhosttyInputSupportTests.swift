//
//  LineyGhosttyInputSupportTests.swift
//  LineyTests
//
//  Author: everettjf
//

import AppKit
import Carbon
import GhosttyKit
import XCTest
@testable import Liney

final class LineyGhosttyInputSupportTests: XCTestCase {
    private let returnKeyCode = UInt16(kVK_Return)
    private let keypadEnterKeyCode = UInt16(kVK_ANSI_KeypadEnter)

    func testShiftReturnUsesTextInputRouting() {
        XCTAssertFalse(
            LineyGhosttyTextInputRouting.shouldPreferRawKeyEvent(
                keyCode: returnKeyCode,
                modifierFlags: [.shift]
            )
        )
    }

    func testCommandReturnStillUsesRawKeyRouting() {
        XCTAssertTrue(
            LineyGhosttyTextInputRouting.shouldPreferRawKeyEvent(
                keyCode: returnKeyCode,
                modifierFlags: [.command]
            )
        )
    }

    func testOptionKeypadEnterStillUsesRawKeyRouting() {
        XCTAssertTrue(
            LineyGhosttyTextInputRouting.shouldPreferRawKeyEvent(
                keyCode: keypadEnterKeyCode,
                modifierFlags: [.option]
            )
        )
    }

    func testPlainReturnDoesNotUseRawKeyRouting() {
        XCTAssertFalse(
            LineyGhosttyTextInputRouting.shouldPreferRawKeyEvent(
                keyCode: returnKeyCode,
                modifierFlags: []
            )
        )
    }

    func testNonReturnKeyNeverUsesRawKeyRouting() {
        XCTAssertFalse(
            LineyGhosttyTextInputRouting.shouldPreferRawKeyEvent(
                keyCode: UInt16(kVK_ANSI_A),
                modifierFlags: [.command]
            )
        )
    }

    func testRawKeyDispatchStaysComposingWhileMarkedTextIsActive() {
        XCTAssertTrue(
            LineyGhosttyTextInputRouting.shouldMarkRawKeyEventAsComposing(
                hadMarkedTextBeforeInterpretation: false,
                hasMarkedTextAfterInterpretation: true
            )
        )
    }

    func testRawKeyDispatchStaysComposingWhenMarkedTextWasJustCleared() {
        XCTAssertTrue(
            LineyGhosttyTextInputRouting.shouldMarkRawKeyEventAsComposing(
                hadMarkedTextBeforeInterpretation: true,
                hasMarkedTextAfterInterpretation: false
            )
        )
    }

    func testRawKeyDispatchIsPlainOutsideComposition() {
        XCTAssertFalse(
            LineyGhosttyTextInputRouting.shouldMarkRawKeyEventAsComposing(
                hadMarkedTextBeforeInterpretation: false,
                hasMarkedTextAfterInterpretation: false
            )
        )
    }

    func testReturnIsNotSentAsLiteralText() {
        XCTAssertFalse(shouldSendGhosttyText("\r"))
        XCTAssertFalse(shouldSendGhosttyText("\n"))
    }

    func testPrintableTextIsStillSent() {
        XCTAssertTrue(shouldSendGhosttyText("a"))
        XCTAssertTrue(shouldSendGhosttyText("你"))
    }

    func testConsumedBindingWithoutActiveSequencesAttemptsMenu() {
        XCTAssertTrue(
            ghosttyShouldAttemptMenu(
                flags: ghostty_binding_flags_e(GHOSTTY_BINDING_FLAGS_CONSUMED.rawValue),
                hasActiveKeySequence: false,
                hasActiveKeyTable: false
            )
        )
    }

    func testPerformableBindingDoesNotAttemptMenu() {
        XCTAssertFalse(
            ghosttyShouldAttemptMenu(
                flags: ghostty_binding_flags_e(
                    GHOSTTY_BINDING_FLAGS_CONSUMED.rawValue | GHOSTTY_BINDING_FLAGS_PERFORMABLE.rawValue
                ),
                hasActiveKeySequence: false,
                hasActiveKeyTable: false
            )
        )
    }

    func testActiveKeySequenceSuppressesMenuAttempt() {
        XCTAssertFalse(
            ghosttyShouldAttemptMenu(
                flags: ghostty_binding_flags_e(GHOSTTY_BINDING_FLAGS_CONSUMED.rawValue),
                hasActiveKeySequence: true,
                hasActiveKeyTable: false
            )
        )
    }

    func testAllBindingDoesNotAttemptMenu() {
        XCTAssertFalse(
            ghosttyShouldAttemptMenu(
                flags: ghostty_binding_flags_e(
                    GHOSTTY_BINDING_FLAGS_CONSUMED.rawValue | GHOSTTY_BINDING_FLAGS_ALL.rawValue
                ),
                hasActiveKeySequence: false,
                hasActiveKeyTable: false
            )
        )
    }

    func testUnboundOptionShortcutStillAttemptsMenu() {
        XCTAssertTrue(
            lineyGhosttyShouldAttemptMenuKeyEquivalent(
                bindingFlags: nil,
                modifierFlags: [.option],
                hasActiveKeySequence: false,
                hasActiveKeyTable: false
            )
        )
    }

    func testPlainUnboundKeyDoesNotAttemptMenu() {
        XCTAssertFalse(
            lineyGhosttyShouldAttemptMenuKeyEquivalent(
                bindingFlags: nil,
                modifierFlags: [],
                hasActiveKeySequence: false,
                hasActiveKeyTable: false
            )
        )
    }

    func testUnboundShortcutSkipsMenuDuringActiveKeySequence() {
        XCTAssertFalse(
            lineyGhosttyShouldAttemptMenuKeyEquivalent(
                bindingFlags: nil,
                modifierFlags: [.option],
                hasActiveKeySequence: true,
                hasActiveKeyTable: false
            )
        )
    }

    func testGhosttySplitRightStopsDispatchingWhenShortcutIsCustomized() {
        var settings = AppSettings()
        LineyKeyboardShortcuts.setShortcut(
            StoredShortcut(key: "d", command: false, shift: false, option: true, control: false),
            for: .splitRight,
            in: &settings
        )

        XCTAssertFalse(
            lineyGhosttyShouldDispatchWorkspaceSplitAction(
                GHOSTTY_SPLIT_DIRECTION_RIGHT,
                settings: settings
            )
        )
    }

    func testGhosttySplitDownStopsDispatchingWhenShortcutIsDisabled() {
        var settings = AppSettings()
        LineyKeyboardShortcuts.disableShortcut(for: .splitDown, in: &settings)

        XCTAssertFalse(
            lineyGhosttyShouldDispatchWorkspaceSplitAction(
                GHOSTTY_SPLIT_DIRECTION_DOWN,
                settings: settings
            )
        )
    }

    func testGhosttySplitRightStillDispatchesWithDefaultShortcut() {
        XCTAssertTrue(
            lineyGhosttyShouldDispatchWorkspaceSplitAction(
                GHOSTTY_SPLIT_DIRECTION_RIGHT,
                settings: AppSettings()
            )
        )
    }

    func testCtrlReturnEquivalentKeyStaysReturn() {
        let resolution = resolveGhosttyEquivalentKey(
            charactersIgnoringModifiers: "\r",
            characters: "\r",
            modifierFlags: [.control],
            eventTimestamp: 42,
            lastPerformKeyEvent: nil
        )

        XCTAssertEqual(resolution.equivalent, "\r")
        XCTAssertNil(resolution.nextLastPerformKeyEvent)
    }

    func testCommandKeyEquivalentRequiresSecondPassToRedispatch() {
        let firstResolution = resolveGhosttyEquivalentKey(
            charactersIgnoringModifiers: "k",
            characters: "k",
            modifierFlags: [.command],
            eventTimestamp: 42,
            lastPerformKeyEvent: nil
        )
        XCTAssertNil(firstResolution.equivalent)
        XCTAssertEqual(firstResolution.nextLastPerformKeyEvent, 42)

        let secondResolution = resolveGhosttyEquivalentKey(
            charactersIgnoringModifiers: "k",
            characters: "k",
            modifierFlags: [.command],
            eventTimestamp: 42,
            lastPerformKeyEvent: firstResolution.nextLastPerformKeyEvent
        )
        XCTAssertEqual(secondResolution.equivalent, "k")
        XCTAssertNil(secondResolution.nextLastPerformKeyEvent)
    }

    func testCtrlSlashEquivalentKeyBecomesUnderscore() {
        let resolution = resolveGhosttyEquivalentKey(
            charactersIgnoringModifiers: "/",
            characters: "/",
            modifierFlags: [.control],
            eventTimestamp: 42,
            lastPerformKeyEvent: nil
        )

        XCTAssertEqual(resolution.equivalent, "_")
        XCTAssertNil(resolution.nextLastPerformKeyEvent)
    }

    func testZeroTimestampDoesNotRedispatchEquivalentKey() {
        let resolution = resolveGhosttyEquivalentKey(
            charactersIgnoringModifiers: "k",
            characters: "k",
            modifierFlags: [.command],
            eventTimestamp: 0,
            lastPerformKeyEvent: 99
        )

        XCTAssertNil(resolution.equivalent)
        XCTAssertEqual(resolution.nextLastPerformKeyEvent, 99)
    }

    func testClampUsesTextLengthForNotFoundSelection() {
        XCTAssertEqual(
            LineyGhosttyMarkedTextState.clamp(NSRange(location: NSNotFound, length: 3), textLength: 5),
            NSRange(location: 5, length: 0)
        )
    }

    func testClampCollapsesEmptyTextSelections() {
        XCTAssertEqual(
            LineyGhosttyMarkedTextState.clamp(NSRange(location: 4, length: 2), textLength: 0),
            NSRange(location: 0, length: 0)
        )
    }

    func testTextFinderActionResolvesFromMenuItemTag() {
        let menuItem = NSMenuItem(title: "Find", action: nil, keyEquivalent: "f")
        menuItem.tag = NSTextFinder.Action.showFindInterface.rawValue

        XCTAssertEqual(lineyTextFinderAction(for: menuItem), .showFindInterface)
    }

    func testTextFinderActionIgnoresUnsupportedSender() {
        XCTAssertNil(lineyTextFinderAction(for: NSObject()))
    }

    func testGhosttySearchBindingActionUsesSearchPrefix() {
        XCTAssertEqual(
            lineyGhosttySearchBindingAction(for: "needle"),
            "search:needle"
        )
    }

    func testGhosttySearchBindingActionPreservesLiteralQueryText() {
        XCTAssertEqual(
            lineyGhosttySearchBindingAction(for: "error: timeout /tmp/a b"),
            "search:error: timeout /tmp/a b"
        )
    }

    func testGhosttySearchBindingActionAllowsEmptyQuery() {
        XCTAssertEqual(
            lineyGhosttySearchBindingAction(for: ""),
            "search:"
        )
    }

    func testGhosttySearchNavigationBindingActionUsesNavigateSearchAction() {
        XCTAssertEqual(
            lineyGhosttySearchNavigationBindingAction(.next),
            "navigate_search:next"
        )
        XCTAssertEqual(
            lineyGhosttySearchNavigationBindingAction(.previous),
            "navigate_search:previous"
        )
    }

    func testTerminalDropTextQuotesFilePathsForShells() {
        let fileURLs = [
            URL(fileURLWithPath: "/tmp/liney screenshot.png"),
            URL(fileURLWithPath: "/tmp/it's-liney.jpg"),
        ]

        XCTAssertEqual(
            lineyTerminalDropText(fileURLs: fileURLs, plainText: nil),
            "'/tmp/liney screenshot.png' '/tmp/it'\\''s-liney.jpg'"
        )
    }

    func testTerminalDropTextFallsBackToPlainText() {
        XCTAssertEqual(
            lineyTerminalDropText(fileURLs: [], plainText: "dragged prompt"),
            "dragged prompt"
        )
    }

    func testDeleteBackwardRemovesSingleComposedCharacter() {
        var state = LineyGhosttyMarkedTextState(
            text: "你好",
            selectedRange: NSRange(location: 2, length: 0)
        )

        state.deleteBackward()

        XCTAssertEqual(state.text, "你")
        XCTAssertEqual(state.selectedRange, NSRange(location: 1, length: 0))
    }

    func testDeleteBackwardRemovesSingleCharacterWhenImeSelectionSpansMarkedText() {
        var state = LineyGhosttyMarkedTextState(
            text: "你好",
            selectedRange: NSRange(location: 0, length: 2)
        )

        state.deleteBackward()

        XCTAssertEqual(state.text, "你")
        XCTAssertEqual(state.selectedRange, NSRange(location: 1, length: 0))
    }

    func testSetMarkedTextHonorsReplacementRangeAndOffsetsSelection() {
        var state = LineyGhosttyMarkedTextState(
            text: "nihao",
            selectedRange: NSRange(location: 5, length: 0)
        )

        state.setMarkedText(
            "u",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: 4, length: 1)
        )

        XCTAssertEqual(state.text, "nihau")
        XCTAssertEqual(state.selectedRange, NSRange(location: 5, length: 0))
    }

    func testAppKitModsReplacesDirectionalModifiersButPreservesFallbackFlags() {
        let mods = ghostty_input_mods_e(GHOSTTY_MODS_ALT.rawValue | GHOSTTY_MODS_SHIFT.rawValue)
        let resolved = appKitMods(mods, fallback: [.capsLock, .command])

        XCTAssertEqual(resolved.intersection([.shift, .option, .command, .capsLock]), [.shift, .option, .capsLock])
    }
}
