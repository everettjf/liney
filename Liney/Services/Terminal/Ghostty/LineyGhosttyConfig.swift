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

        if let scrollbackLines = settings.terminalScrollbackLines {
            lines.append("scrollback-limit = \(scrollbackLines)")
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

    private static func quotedValue(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
