//
//  TerminalInlineImageFilter.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

/// Opt-in support for iTerm2 OSC 1337 inline images (the protocol Claude Code
/// and similar tools use to print screenshots).
///
/// Ghostty does not understand OSC 1337, but it natively renders the Kitty
/// graphics protocol. The bundled `liney-osc-filter` helper is a transparent PTY
/// relay that rewrites OSC 1337 image sequences into Kitty graphics on the fly.
/// When enabled, we launch the terminal command *through* that helper instead of
/// directly, so the translation is invisible to both the shell and Ghostty.
///
/// This is wrapping the core terminal launch, so it is deliberately opt-in and
/// fails safe: if the setting is off or the helper can't be located, the command
/// is returned untouched and the terminal behaves exactly as before.
enum TerminalInlineImageFilter {
    /// UserDefaults key backing the Settings toggle. Defaults to `false`
    /// (feature off) when unset.
    static let defaultsKey = "liney.terminal.inlineImageProtocol"

    /// File name of the helper compiled into the app bundle's Resources by the
    /// "Compile OSC Filter" build phase.
    private static let helperResourceName = "liney-osc-filter"

    /// Enabled by default. When the user has never touched the toggle the key is
    /// absent, and we treat that as on; once they flip it, their stored choice
    /// (on or off) is honored. This must match the `@AppStorage` default in the
    /// Settings toggle.
    static var isEnabled: Bool {
        guard UserDefaults.standard.object(forKey: defaultsKey) != nil else {
            return true
        }
        return UserDefaults.standard.bool(forKey: defaultsKey)
    }

    /// Absolute path to the bundled helper, or `nil` if it isn't present (e.g. a
    /// build that didn't run the compile phase). Resolving lazily keeps this
    /// usable from non-main-actor launch code.
    static var helperPath: String? {
        Bundle.main.url(forResource: helperResourceName, withExtension: nil)?.path
    }

    /// Returns a command that runs `command` through the inline-image helper when
    /// the feature is enabled and the helper exists; otherwise returns `command`
    /// unchanged.
    static func applyIfEnabled(to command: TerminalCommandDefinition) -> TerminalCommandDefinition {
        guard isEnabled, let helperPath else { return command }
        return wrapped(command: command, helperPath: helperPath)
    }

    /// Pure wrapping logic, exposed for testing. Prefixes `command` with the
    /// helper so the original executable becomes the helper's first argument.
    /// Returns `command` unchanged for an empty executable or one that is already
    /// the helper (guards against double-wrapping on session restore).
    static func wrapped(command: TerminalCommandDefinition, helperPath: String) -> TerminalCommandDefinition {
        guard !command.executablePath.isEmpty, command.executablePath != helperPath else {
            return command
        }
        return TerminalCommandDefinition(
            executablePath: helperPath,
            arguments: [command.executablePath] + command.arguments,
            displayName: command.displayName
        )
    }
}
