//
//  PathFormatting.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

extension String {
    nonisolated var abbreviatedPath: String {
        let home = NSHomeDirectory()
        if hasPrefix(home) {
            return "~" + dropFirst(home.count)
        }
        return self
    }

    nonisolated var lastPathComponentValue: String {
        URL(fileURLWithPath: self).lastPathComponent
    }

    nonisolated var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Backslash-escaped form for inserting a path into an interactive shell
    /// without wrapping quotes, e.g. `/Users/me/Screen\ Studio`. Every ASCII
    /// character outside a conservative safe set (letters, digits, and
    /// `_-./@%+=:,`) is prefixed with a backslash, so spaces and shell
    /// metacharacters like `( ) & $ ' "` are neutralized. Non-ASCII characters
    /// (e.g. CJK) need no shell escaping and are kept as-is.
    nonisolated var shellEscaped: String {
        if isEmpty { return "''" }
        let safe = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-./@%+=:,")
        var out = ""
        out.reserveCapacity(count)
        for character in self {
            if character.isASCII, !safe.contains(character) {
                out.append("\\")
            }
            out.append(character)
        }
        return out
    }
}
