//
//  HooksSettingsView.swift
//  Liney
//
//  Author: everettjf
//

import AppKit
import SwiftUI

struct HooksSettingsView: View {
    @Binding var appSettings: AppSettings
    @State private var fileExists: Bool = false
    @State private var fileURL: URL = HookSettingsPersistence().fileURL
    @State private var logURL: URL = HookSettingsPersistence().logFileURL
    @State private var scriptsURL: URL = HookSettingsPersistence().stateDirectoryURL.appendingPathComponent("hooks", isDirectory: true)

    private let persistence = HookSettingsPersistence()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox(localized("settings.hooks.enable.group")) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(localized("settings.hooks.enable.toggle"), isOn: $appSettings.hooksEnabled)

                    Text(localized("settings.hooks.enable.description"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text(localized("settings.hooks.docs.hint"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }

            GroupBox(localized("settings.hooks.file.group")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text(localized("settings.hooks.file.path"))
                            .foregroundStyle(.secondary)
                        Text(fileURL.path)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    if !fileExists {
                        Text(localized("settings.hooks.file.notExistHint"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(localizedFormat("settings.hooks.file.exists", fileURL.path))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        Button(localized("settings.hooks.file.openButton")) {
                            openHooksFile()
                        }
                        Button(localized("settings.hooks.file.revealButton")) {
                            revealHooksFile()
                        }
                        .disabled(!fileExists)
                    }
                }
                .padding(.top, 8)
            }

            GroupBox(localized("settings.hooks.scripts.group")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text(localized("settings.hooks.scripts.path"))
                            .foregroundStyle(.secondary)
                        Text(scriptsURL.path)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Text(localized("settings.hooks.scripts.hint"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Button(localized("settings.hooks.scripts.revealButton")) {
                            revealScriptsFolder()
                        }
                    }
                }
                .padding(.top, 8)
            }

            GroupBox(localized("settings.hooks.log.group")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(localized("settings.hooks.log.hint"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Button(localized("settings.hooks.log.openButton")) {
                            openLogFile()
                        }
                        .disabled(!FileManager.default.fileExists(atPath: logURL.path))

                        Button(localized("settings.hooks.log.clearButton")) {
                            HookLogger.shared.clear()
                        }
                        .disabled(!FileManager.default.fileExists(atPath: logURL.path))
                    }
                }
                .padding(.top, 8)
            }
        }
        .onAppear { refreshState() }
    }

    private func localized(_ key: String) -> String {
        LocalizationManager.shared.string(key)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        l10nFormat(localized(key), locale: Locale.current, arguments: arguments)
    }

    private func refreshState() {
        fileURL = persistence.fileURL
        logURL = persistence.logFileURL
        fileExists = FileManager.default.fileExists(atPath: fileURL.path)
    }

    private func openHooksFile() {
        if !fileExists {
            do {
                try persistence.ensureFileExists()
                HookRunner.shared.invalidateCache()
                fileExists = true
            } catch {
                NSAlert(error: error).runModal()
                return
            }
        }
        NSWorkspace.shared.open(fileURL)
    }

    private func revealHooksFile() {
        guard fileExists else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    private func openLogFile() {
        guard FileManager.default.fileExists(atPath: logURL.path) else { return }
        NSWorkspace.shared.open(logURL)
    }

    private func revealScriptsFolder() {
        try? FileManager.default.createDirectory(at: scriptsURL, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([scriptsURL])
    }
}
