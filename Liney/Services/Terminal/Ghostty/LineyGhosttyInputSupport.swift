//
//  LineyGhosttyInputSupport.swift
//  Liney
//
//  Author: everettjf
//

import AppKit
import Carbon
import GhosttyKit

enum LineyGhosttyTextInputRouting {
    static func shouldPreferRawKeyEvent(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        guard keyCode == UInt16(kVK_Return) || keyCode == UInt16(kVK_ANSI_KeypadEnter) else {
            return false
        }
        return modifierFlags.intersection([.option, .command, .control]).isEmpty == false
    }

    static func shouldMarkRawKeyEventAsComposing(
        hadMarkedTextBeforeInterpretation: Bool,
        hasMarkedTextAfterInterpretation: Bool
    ) -> Bool {
        hadMarkedTextBeforeInterpretation || hasMarkedTextAfterInterpretation
    }
}

struct LineyGhosttyMarkedTextState: Equatable {
    var text: String
    var selectedRange: NSRange

    init(text: String, selectedRange: NSRange) {
        self.text = text
        self.selectedRange = Self.clamp(selectedRange, textLength: (text as NSString).length)
    }

    mutating func setMarkedText(_ replacementText: String, selectedRange: NSRange, replacementRange: NSRange) {
        let nsText = text as NSString
        let resolvedReplacementRange = Self.markedReplacementRange(replacementRange, textLength: nsText.length)
        text = nsText.replacingCharacters(in: resolvedReplacementRange, with: replacementText)

        var adjustedSelection = selectedRange
        if adjustedSelection.location != NSNotFound {
            adjustedSelection.location += resolvedReplacementRange.location
        }
        self.selectedRange = Self.clamp(adjustedSelection, textLength: (text as NSString).length)
    }

    mutating func deleteBackward() {
        let nsText = text as NSString
        let textLength = nsText.length
        let safeSelection = Self.clamp(selectedRange, textLength: textLength)
        let insertionLocation = safeSelection.length > 0 ? NSMaxRange(safeSelection) : safeSelection.location

        guard insertionLocation > 0 else {
            selectedRange = NSRange(location: 0, length: 0)
            return
        }

        let deleteRange = nsText.rangeOfComposedCharacterSequence(at: insertionLocation - 1)
        text = nsText.replacingCharacters(in: deleteRange, with: "")
        selectedRange = NSRange(location: deleteRange.location, length: 0)
    }

    private static func markedReplacementRange(_ replacementRange: NSRange, textLength: Int) -> NSRange {
        guard replacementRange.location != NSNotFound else {
            return NSRange(location: 0, length: textLength)
        }
        return clamp(replacementRange, textLength: textLength)
    }

    static func clamp(_ range: NSRange, textLength: Int) -> NSRange {
        guard textLength > 0 else {
            return NSRange(location: 0, length: 0)
        }

        let location: Int
        if range.location == NSNotFound {
            location = textLength
        } else {
            location = min(max(range.location, 0), textLength)
        }
        let length = min(max(range.length, 0), textLength - location)
        return NSRange(location: location, length: length)
    }
}

struct LineyGhosttyEquivalentKeyResolution: Equatable {
    let equivalent: String?
    let nextLastPerformKeyEvent: TimeInterval?
}

func ghosttyMods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
    var mods: UInt32 = GHOSTTY_MODS_NONE.rawValue

    if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
    if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
    if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
    if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
    if flags.contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }

    let rawFlags = flags.rawValue
    if rawFlags & UInt(NX_DEVICERSHIFTKEYMASK) != 0 { mods |= GHOSTTY_MODS_SHIFT_RIGHT.rawValue }
    if rawFlags & UInt(NX_DEVICERCTLKEYMASK) != 0 { mods |= GHOSTTY_MODS_CTRL_RIGHT.rawValue }
    if rawFlags & UInt(NX_DEVICERALTKEYMASK) != 0 { mods |= GHOSTTY_MODS_ALT_RIGHT.rawValue }
    if rawFlags & UInt(NX_DEVICERCMDKEYMASK) != 0 { mods |= GHOSTTY_MODS_SUPER_RIGHT.rawValue }

    return ghostty_input_mods_e(mods)
}

func appKitMods(_ mods: ghostty_input_mods_e, fallback: NSEvent.ModifierFlags = []) -> NSEvent.ModifierFlags {
    var flags = fallback

    for flag in [NSEvent.ModifierFlags.shift, .control, .option, .command] {
        flags.remove(flag)
    }

    if mods.rawValue & GHOSTTY_MODS_SHIFT.rawValue != 0 { flags.insert(.shift) }
    if mods.rawValue & GHOSTTY_MODS_CTRL.rawValue != 0 { flags.insert(.control) }
    if mods.rawValue & GHOSTTY_MODS_ALT.rawValue != 0 { flags.insert(.option) }
    if mods.rawValue & GHOSTTY_MODS_SUPER.rawValue != 0 { flags.insert(.command) }

    return flags
}

func textForGhosttyKeyEvent(_ event: NSEvent) -> String? {
    guard let characters = event.characters, !characters.isEmpty else { return nil }

    if characters.count == 1, let scalar = characters.unicodeScalars.first {
        if isGhosttyControlCharacterScalar(scalar) {
            if event.modifierFlags.contains(.control) {
                return event.characters(byApplyingModifiers: event.modifierFlags.subtracting(.control))
            }
        }

        if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
            return nil
        }
    }

    return characters
}

func shouldSendGhosttyText(_ text: String) -> Bool {
    guard !text.isEmpty else { return false }
    if text.count == 1, let scalar = text.unicodeScalars.first {
        return !isGhosttyControlCharacterScalar(scalar)
    }
    return true
}

func isGhosttyControlCharacterScalar(_ scalar: UnicodeScalar) -> Bool {
    scalar.value < 0x20 || scalar.value == 0x7F
}

func ghosttyShouldAttemptMenu(
    flags: ghostty_binding_flags_e,
    hasActiveKeySequence: Bool,
    hasActiveKeyTable: Bool
) -> Bool {
    if hasActiveKeySequence || hasActiveKeyTable {
        return false
    }

    let rawFlags = flags.rawValue
    let isAll = (rawFlags & GHOSTTY_BINDING_FLAGS_ALL.rawValue) != 0
    let isPerformable = (rawFlags & GHOSTTY_BINDING_FLAGS_PERFORMABLE.rawValue) != 0
    let isConsumed = (rawFlags & GHOSTTY_BINDING_FLAGS_CONSUMED.rawValue) != 0
    return !isAll && !isPerformable && isConsumed
}

func lineyGhosttyShouldAttemptMenuKeyEquivalent(
    bindingFlags: ghostty_binding_flags_e?,
    modifierFlags: NSEvent.ModifierFlags,
    hasActiveKeySequence: Bool,
    hasActiveKeyTable: Bool
) -> Bool {
    if let bindingFlags {
        return ghosttyShouldAttemptMenu(
            flags: bindingFlags,
            hasActiveKeySequence: hasActiveKeySequence,
            hasActiveKeyTable: hasActiveKeyTable
        )
    }

    guard !hasActiveKeySequence, !hasActiveKeyTable else {
        return false
    }

    let relevantModifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
    return relevantModifiers.intersection([.command, .control, .option]).isEmpty == false
}

func lineyGhosttyShouldDispatchWorkspaceSplitAction(
    _ direction: ghostty_action_split_direction_e,
    settings: AppSettings
) -> Bool {
    switch direction {
    case GHOSTTY_SPLIT_DIRECTION_RIGHT:
        return LineyKeyboardShortcuts.effectiveShortcut(for: .splitRight, in: settings) ==
            LineyShortcutAction.splitRight.defaultShortcut
    case GHOSTTY_SPLIT_DIRECTION_DOWN:
        return LineyKeyboardShortcuts.effectiveShortcut(for: .splitDown, in: settings) ==
            LineyShortcutAction.splitDown.defaultShortcut
    default:
        return true
    }
}

func resolveGhosttyEquivalentKey(
    charactersIgnoringModifiers: String?,
    characters: String?,
    modifierFlags: NSEvent.ModifierFlags,
    eventTimestamp: TimeInterval,
    lastPerformKeyEvent: TimeInterval?
) -> LineyGhosttyEquivalentKeyResolution {
    switch charactersIgnoringModifiers {
    case "\r":
        guard modifierFlags.contains(.control) else {
            return LineyGhosttyEquivalentKeyResolution(equivalent: nil, nextLastPerformKeyEvent: lastPerformKeyEvent)
        }
        return LineyGhosttyEquivalentKeyResolution(equivalent: "\r", nextLastPerformKeyEvent: nil)

    case "/":
        guard modifierFlags.contains(.control),
              modifierFlags.isDisjoint(with: [.shift, .command, .option]) else {
            return LineyGhosttyEquivalentKeyResolution(equivalent: nil, nextLastPerformKeyEvent: lastPerformKeyEvent)
        }
        return LineyGhosttyEquivalentKeyResolution(equivalent: "_", nextLastPerformKeyEvent: nil)

    default:
        guard eventTimestamp != 0 else {
            return LineyGhosttyEquivalentKeyResolution(equivalent: nil, nextLastPerformKeyEvent: lastPerformKeyEvent)
        }

        guard modifierFlags.contains(.command) || modifierFlags.contains(.control) else {
            return LineyGhosttyEquivalentKeyResolution(equivalent: nil, nextLastPerformKeyEvent: nil)
        }

        if let lastPerformKeyEvent, lastPerformKeyEvent == eventTimestamp {
            return LineyGhosttyEquivalentKeyResolution(
                equivalent: characters ?? "",
                nextLastPerformKeyEvent: nil
            )
        }

        return LineyGhosttyEquivalentKeyResolution(equivalent: nil, nextLastPerformKeyEvent: eventTimestamp)
    }
}

extension NSEvent {
    func ghosttyKeyEvent(
        _ action: ghostty_input_action_e,
        translationMods: NSEvent.ModifierFlags? = nil,
        composing: Bool = false
    ) -> ghostty_input_key_s {
        var event = ghostty_input_key_s()
        event.action = action
        event.keycode = UInt32(keyCode)
        event.text = nil
        event.composing = composing
        event.mods = ghosttyMods(modifierFlags)
        event.consumed_mods = ghosttyMods((translationMods ?? modifierFlags).subtracting([.control, .command]))
        event.unshifted_codepoint = 0

        if type == .keyDown || type == .keyUp,
           let chars = characters(byApplyingModifiers: []),
           let codepoint = chars.unicodeScalars.first {
            event.unshifted_codepoint = codepoint.value
        }

        return event
    }

    var ghosttyCharacters: String? {
        guard let characters else { return nil }

        if characters.count == 1, let scalar = characters.unicodeScalars.first {
            if scalar.value < 0x20 {
                return self.characters(byApplyingModifiers: modifierFlags.subtracting(.control))
            }
            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
                return nil
            }
        }

        return characters
    }
}
