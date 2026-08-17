//
//  LineyGhosttyConfig.swift
//  Liney
//
//  Author: everettjf
//

import Foundation
import GhosttyKit

enum LineyGhosttyConfigManager {
    static let defaultTheme = "Catppuccin Mocha"

    static func buildConfig(
        settings: AppSettings,
        fileManager: FileManager = .default
    ) throws -> ghostty_config_t {
        guard let config = ghostty_config_new() else {
            throw CocoaError(.coderInvalidValue)
        }

        ghostty_config_load_default_files(config)

        let managedConfigURL = try writeManagedConfig(settings: settings, fileManager: fileManager)
        managedConfigURL.path.withCString { path in
            ghostty_config_load_file(config, path)
        }
        ghostty_config_finalize(config)
        return config
    }

    static func writeManagedConfig(
        settings: AppSettings,
        fileManager: FileManager = .default
    ) throws -> URL {
        let fileURL = managedConfigFileURL(fileManager: fileManager)
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try managedConfigContents(settings: settings)
            .write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    static func managedConfigContents(settings: AppSettings) -> String {
        var lines = [
            "# Managed by Liney. Manual edits will be overwritten."
        ]

        if let themeName = settings.terminalTheme {
            if let themeContents = readThemeFileContents(named: themeName) {
                // Inline the theme colors directly so that ghostty_config_load_file
                // picks them up without relying on Ghostty's own theme lookup.
                lines.append("# theme: \(themeName)")
                lines.append(themeContents)
            } else {
                // Fallback: let Ghostty resolve the theme by name.
                lines.append("theme = \(themeName)")
            }
        }
        // When terminalTheme is nil, no theme config is written so Ghostty
        // uses its native dark default (black background).

        if let terminalFontFamily = settings.terminalFontFamily {
            lines.append("font-family = \(quotedValue(terminalFontFamily))")
        }

        if let terminalFontSize = settings.terminalFontSize {
            lines.append("font-size = \(Int(terminalFontSize.rounded()))")
        }

        // Ghostty's `scrollback-limit` is a byte budget, so emit the stored
        // byte value directly (see TerminalScrollback).
        if let scrollbackBytes = settings.terminalScrollbackBytes {
            lines.append("scrollback-limit = \(scrollbackBytes)")
        }

        // Only emit background-opacity when the terminal is meant to be
        // translucent. At full opacity we leave it unset so Ghostty keeps its
        // default opaque background (and the host view stays fully opaque).
        if settings.terminalBackgroundOpacity < 1 {
            let opacity = min(max(settings.terminalBackgroundOpacity, 0.5), 1)
            lines.append("background-opacity = \(String(format: "%.2f", opacity))")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func readThemeFileContents(named name: String) -> String? {
        guard let path = LineyGhosttyThemeCatalog.findThemeFile(named: name),
              let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        // Strip comments and blank lines, keep only key = value lines.
        return contents
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .joined(separator: "\n")
    }

    static func managedConfigFileURL(fileManager: FileManager = .default) -> URL {
        lineyStateDirectoryURL(fileManager: fileManager)
            .appendingPathComponent("ghostty", isDirectory: true)
            .appendingPathComponent("liney-managed.config")
    }

    /// Returns Ghostty's normal user config file, creating it when needed.
    /// Liney loads this file before its generated managed overrides.
    static func openUserConfigFileURL() -> URL? {
        let path = ghostty_config_open_path()
        defer { ghostty_string_free(path) }
        guard let pointer = path.ptr, path.len > 0 else { return nil }
        let bytes = UnsafeRawPointer(pointer).assumingMemoryBound(to: UInt8.self)
        return URL(fileURLWithPath: String(decoding: UnsafeBufferPointer(start: bytes, count: Int(path.len)), as: UTF8.self))
    }

    private static func quotedValue(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
