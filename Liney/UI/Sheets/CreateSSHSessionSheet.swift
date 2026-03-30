//
//  CreateSSHSessionSheet.swift
//  Liney
//
//  Author: everettjf
//

import SwiftUI

struct CreateSSHSessionSheet: View {
    let request: CreateSSHSessionRequest
    let onCreate: (CreateSSHSessionDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = CreateSSHSessionDraft()

    private var existingTargets: [RemoteWorkspaceTarget] {
        request.remoteTargets
    }

    private var availablePresets: [SSHPreset] {
        request.presets
    }

    private var shouldRequireTargetName: Bool {
        draft.saveAsTarget || draft.selectedTargetID != nil
    }

    private func localized(_ key: String) -> String {
        LocalizationManager.shared.string(key)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        l10nFormat(localized(key), locale: Locale.current, arguments: arguments)
    }

    private func applySelectedTarget(_ targetID: UUID?) {
        guard let targetID,
              let target = existingTargets.first(where: { $0.id == targetID }) else {
            return
        }
        draft.apply(remoteTarget: target)
    }

    private func applySelectedPreset(_ presetID: UUID?) {
        guard let presetID,
              let preset = availablePresets.first(where: { $0.id == presetID }) else {
            return
        }
        draft.apply(sshPreset: preset)
    }

    private var canCreate: Bool {
        guard draft.configuration != nil else { return false }
        if shouldRequireTargetName {
            return draft.normalizedTargetName.nilIfEmpty != nil
        }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localized("sheet.ssh.title"))
                .font(.system(size: 18, weight: .semibold))

            Text(localizedFormat("sheet.ssh.descriptionFormat", request.workspaceName))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if !availablePresets.isEmpty {
                GroupBox(localized("sheet.ssh.preset")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker(localized("sheet.ssh.preset"), selection: $draft.selectedPresetID) {
                            ForEach(availablePresets) { preset in
                                Text(preset.name).tag(Optional(preset.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.top, 8)
                }
                .onChange(of: draft.selectedPresetID) { _, newValue in
                    applySelectedPreset(newValue)
                }
            }

            if !existingTargets.isEmpty {
                GroupBox(localized("sheet.ssh.savedTargets")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker(localized("sheet.ssh.savedTargets"), selection: $draft.selectedTargetID) {
                            Text(localized("sheet.ssh.savedTargetsNone"))
                                .tag(UUID?.none)
                            ForEach(existingTargets) { target in
                                Text("\(target.name) · \(target.ssh.destination)")
                                    .tag(Optional(target.id))
                            }
                        }
                        .pickerStyle(.menu)

                        Text(localized("sheet.ssh.savedTargetsHint"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }
                .onChange(of: draft.selectedTargetID) { _, newValue in
                    applySelectedTarget(newValue)
                }
            }

            GroupBox(localized("sheet.ssh.connection")) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField(localized("sheet.ssh.host"), text: $draft.host)
                    TextField(localized("sheet.ssh.user"), text: $draft.user)
                    TextField(localized("sheet.ssh.port"), text: $draft.port)
                    TextField(localized("sheet.ssh.identityFile"), text: $draft.identityFilePath)
                    TextField(localized("sheet.ssh.remoteWorkingDirectory"), text: $draft.remoteWorkingDirectory)
                }
                .textFieldStyle(.roundedBorder)
                .padding(.top, 8)
            }

            GroupBox(localized("sheet.ssh.command")) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField(localized("sheet.ssh.remoteCommand"), text: $draft.remoteCommand, axis: .vertical)
                }
                .textFieldStyle(.roundedBorder)
                .padding(.top, 8)
            }

            GroupBox(localized("sheet.ssh.target")) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(localized("sheet.ssh.saveAsTarget"), isOn: $draft.saveAsTarget)
                    TextField(localized("sheet.ssh.targetName"), text: $draft.targetName)
                        .disabled(!shouldRequireTargetName)
                    Text(localized("sheet.ssh.targetHint"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .textFieldStyle(.roundedBorder)
                .padding(.top, 8)
            }

            HStack {
                Spacer()
                Button(localized("common.cancel")) {
                    dismiss()
                }
                Button(localized("sheet.ssh.create")) {
                    onCreate(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canCreate)
            }
        }
        .onAppear {
            draft.remoteWorkingDirectory = request.defaultWorkingDirectory
            draft.selectedPresetID = request.preferredPresetID ?? availablePresets.first?.id
            if let presetID = draft.selectedPresetID {
                applySelectedPreset(presetID)
            }
            if let firstTarget = existingTargets.first {
                draft.selectedTargetID = firstTarget.id
                draft.apply(remoteTarget: firstTarget)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
