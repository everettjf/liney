//
//  LightweightEditorSheet.swift
//  Liney
//

import SwiftUI

struct LightweightEditorSheet: View {
    let request: LightweightEditorRequest
    let onSave: (String) -> Void

    @ObservedObject private var localization = LocalizationManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var contents: String
    @State private var lastSavedContents: String

    init(request: LightweightEditorRequest, onSave: @escaping (String) -> Void) {
        self.request = request
        self.onSave = onSave
        _contents = State(initialValue: request.initialContents)
        _lastSavedContents = State(initialValue: request.initialContents)
    }

    private func localized(_ key: String) -> String {
        localization.string(key)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        l10nFormat(localized(key), locale: Locale.current, arguments: arguments)
    }

    private var hasUnsavedChanges: Bool {
        contents != lastSavedContents
    }

    private var fileName: String {
        URL(fileURLWithPath: request.filePath).lastPathComponent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(fileName)
                        .font(.title3.weight(.semibold))
                    if hasUnsavedChanges {
                        Text(localized("sheet.editor.unsaved"))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(LineyTheme.warning.opacity(0.16), in: Capsule())
                            .foregroundStyle(LineyTheme.warning)
                    }
                }
                Text(localizedFormat("sheet.editor.subtitleFormat", request.workspaceName))
                    .font(.subheadline)
                    .foregroundStyle(LineyTheme.secondaryText)
                Text(request.filePath)
                    .font(.caption.monospaced())
                    .foregroundStyle(LineyTheme.tertiaryText)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }

            TextEditor(text: $contents)
                .font(.system(.body, design: .monospaced))
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LineyTheme.panelRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(LineyTheme.border, lineWidth: 1)
                )

            HStack {
                Button(localized("common.cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(localized("sheet.editor.revert")) {
                    contents = lastSavedContents
                }
                .disabled(!hasUnsavedChanges)

                Spacer()

                Button(localized("sheet.editor.save")) {
                    onSave(contents)
                    lastSavedContents = contents
                    dismiss()
                }
                .keyboardShortcut("s", modifiers: [.command])
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 520)
    }
}
