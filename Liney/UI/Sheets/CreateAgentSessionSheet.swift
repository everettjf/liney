//
//  CreateAgentSessionSheet.swift
//  Liney
//
//  Author: everettjf
//

import SwiftUI

struct CreateAgentSessionSheet: View {
    let request: CreateAgentSessionRequest
    let onCreate: (CreateAgentSessionDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = CreateAgentSessionDraft()
    @State private var selectedPresetID: UUID?

    private func localized(_ key: String) -> String {
        LocalizationManager.shared.string(key)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        l10nFormat(localized(key), locale: Locale.current, arguments: arguments)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localized("sheet.agent.title"))
                .font(.system(size: 18, weight: .semibold))

            Text(localizedFormat("sheet.agent.descriptionFormat", request.workspaceName))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if !request.presets.isEmpty {
                Picker(localized("sheet.agent.preset"), selection: Binding(
                    get: { selectedPresetID ?? request.preferredPresetID ?? request.presets.first?.id },
                    set: { newValue in
                        selectedPresetID = newValue
                        draft.selectedPresetID = newValue
                        if let newValue,
                           let preset = request.presets.first(where: { $0.id == newValue }) {
                            draft.apply(preset: preset)
                        }
                    }
                )) {
                    ForEach(request.presets) { preset in
                        Text(preset.name).tag(Optional(preset.id))
                    }
                }
            }

            GroupBox(localized("sheet.agent.executable")) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField(localized("sheet.agent.displayName"), text: $draft.name)
                    TextField(localized("sheet.agent.launchPath"), text: $draft.launchPath)
                    TextField(localized("sheet.agent.workingDirectory"), text: $draft.workingDirectory)
                }
                .textFieldStyle(.roundedBorder)
                .padding(.top, 8)
            }

            GroupBox(localized("sheet.agent.arguments")) {
                TextEditor(text: $draft.argumentsText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 110)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08)))
                    .padding(.top, 8)
            }

            GroupBox(localized("sheet.agent.environment")) {
                TextEditor(text: $draft.environmentText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 90)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08)))
                    .padding(.top, 8)
            }

            LabeledContent(localized("sheet.shared.engine"), value: TerminalEngineKind.libghosttyPreferred.displayName)

            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Label(localized("common.cancel"), systemImage: "xmark")
                }
                Button {
                    onCreate(draft)
                    dismiss()
                } label: {
                    Label(localized("sheet.agent.create"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.configuration == nil)
            }
        }
        .padding(20)
        .frame(width: 560)
        .task {
            selectedPresetID = request.preferredPresetID ?? request.presets.first?.id
            draft.selectedPresetID = selectedPresetID
            if let selectedPresetID,
               let preset = request.presets.first(where: { $0.id == selectedPresetID }) {
                draft.apply(preset: preset)
            } else {
                draft.workingDirectory = request.defaultWorkingDirectory
            }
        }
    }
}
