//
//  WorkflowEditorSheet.swift
//  Liney
//
//  Author: everettjf
//

import SwiftUI

struct WorkflowEditorSheet: View {
    @EnvironmentObject private var store: WorkspaceStore

    let workspaceID: UUID

    var body: some View {
        if let workspace = store.workspaces.first(where: { $0.id == workspaceID }) {
            WorkflowEditorContent(workspace: workspace)
        }
    }
}

private struct WorkflowEditorContent: View {
    @ObservedObject var workspace: WorkspaceModel
    @EnvironmentObject private var store: WorkspaceStore
    @ObservedObject private var localization = LocalizationManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedWorkflowID: UUID?

    private func localized(_ key: String) -> String {
        LocalizationManager.shared.string(key)
    }

    var body: some View {
        ZStack {
            LineyTheme.appBackground

            VStack(spacing: 0) {
                // Top bar
                HStack(alignment: .center) {
                    Text(localized("sheet.workflowEditor.title"))
                        .font(.system(size: 19, weight: .semibold))
                    Text("— \(workspace.name)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 10)
                .background(LineyTheme.panelBackground.opacity(0.98))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(LineyTheme.border).frame(height: 1)
                }

                // Split view
                HStack(spacing: 0) {
                    sidebar
                    Divider()
                    detailPane
                }

                // Footer
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Label(localized("sheet.workflowEditor.done"), systemImage: "checkmark")
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(LineyTheme.panelBackground.opacity(0.98))
                .overlay(alignment: .top) {
                    Rectangle().fill(LineyTheme.border).frame(height: 1)
                }
            }
        }
        .frame(width: 960, height: 640)
        .padding(12)
        .background(
            LineyTheme.panelBackground,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(LineyTheme.border, lineWidth: 1)
        )
        .task {
            selectedWorkflowID = workspace.workflows.first?.id
        }
    }

    // MARK: - Sidebar

    private static let presetWorkflows: [(name: String, commands: [(name: String, command: String)])] = [
        (
            name: "HAPI Relay",
            commands: [
                (name: "Hub", command: "hapi hub --relay"),
                (name: "HAPI", command: "hapi"),
            ]
        ),
        (
            name: "HAPI Tunnel",
            commands: [
                (name: "Hub", command: "hapi hub"),
                (name: "HAPI", command: "hapi"),
                (name: "Tunnel", command: "cloudflared tunnel run hapi"),
            ]
        ),
    ]

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    let newWorkflow = WorkspaceWorkflow(name: localized("defaults.workflow.name"))
                    workspace.settings.workflows.append(newWorkflow)
                    selectedWorkflowID = newWorkflow.id
                } label: {
                    Label(localized("sheet.workflowEditor.addWorkflow"), systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                }

                Menu {
                    ForEach(Self.presetWorkflows, id: \.name) { preset in
                        Button(preset.name) {
                            let commands = preset.commands.map {
                                WorkspaceWorkflowBatchCommand(name: $0.name, command: $0.command)
                            }
                            let workflow = WorkspaceWorkflow(name: preset.name, commands: commands)
                            workspace.settings.workflows.append(workflow)
                            selectedWorkflowID = workflow.id
                        }
                    }
                } label: {
                    Label(localized("sheet.workflowEditor.presets"), systemImage: "square.and.arrow.down")
                        .font(.system(size: 12, weight: .medium))
                }
            }

            if workspace.workflows.isEmpty {
                Text(localized("settings.workspace.workflowsHint"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(workspace.workflows) { workflow in
                            workflowListItem(workflow: workflow)
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(16)
        .frame(width: 260)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(LineyTheme.appBackground.opacity(0.16))
    }

    private func workflowListItem(workflow: WorkspaceWorkflow) -> some View {
        let isSelected = workflow.id == selectedWorkflowID
        return Button {
            selectedWorkflowID = workflow.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.rectangle.on.rectangle")
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? .white : LineyTheme.secondaryText)

                VStack(alignment: .leading, spacing: 2) {
                    Text(workflow.name.isEmpty ? localized("defaults.workflow.name") : workflow.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isSelected ? .white : .primary)
                        .lineLimit(1)

                    Text(workflow.commands.isEmpty
                         ? localized("sheet.workflowEditor.noCommands")
                         : "\(workflow.commands.count) \(localized("sheet.workflowEditor.commandsSuffix"))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(isSelected ? .white.opacity(0.7) : LineyTheme.mutedText)
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isSelected ? LineyTheme.accent : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail Pane

    private var detailPane: some View {
        Group {
            if let workflowID = selectedWorkflowID,
               let wi = workspace.workflows.firstIndex(where: { $0.id == workflowID }) {
                workflowDetail(workspace: workspace, workflowIndex: wi, workflowID: workflowID)
            } else {
                Text(localized("sheet.workflowEditor.selectWorkflow"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func workflowDetail(workspace: WorkspaceModel, workflowIndex wi: Int, workflowID: UUID) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Name + delete
                HStack {
                    TextField(
                        localized("settings.workspace.workflow.name"),
                        text: Binding(
                            get: { workspace.workflows[safe: wi]?.name ?? "" },
                            set: { if wi < workspace.settings.workflows.count { workspace.settings.workflows[wi].name = $0 } }
                        )
                    )
                    .font(.system(size: 15, weight: .medium))
                    .textFieldStyle(.plain)

                    Spacer()

                    Button(role: .destructive) {
                        workspace.settings.workflows.removeAll { $0.id == workflowID }
                        selectedWorkflowID = workspace.workflows.first?.id
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }

                Divider()

                // Batch commands
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(localized("settings.workspace.workflow.batchCommands"))
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Button {
                            if wi < workspace.settings.workflows.count {
                                workspace.settings.workflows[wi].commands.append(WorkspaceWorkflowBatchCommand())
                            }
                        } label: {
                            Label(localized("settings.workspace.workflow.addBatchCommand"), systemImage: "plus")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }

                    let workflow = workspace.workflows[wi]
                    ForEach(workflow.commands) { cmd in
                        if let ci = workflow.commands.firstIndex(where: { $0.id == cmd.id }) {
                            commandCard(workspace: workspace, wi: wi, ci: ci, commandID: cmd.id)
                        }
                    }

                    if workspace.workflows[safe: wi]?.commands.isEmpty ?? true {
                        Text(localized("settings.workspace.workflow.batchCommandsHint"))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 4)
                    }
                }

                Divider()

                // Advanced
                DisclosureGroup(localized("settings.workspace.workflow.advanced")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker(localized("settings.workspace.workflow.localShell"), selection: Binding(
                            get: { workspace.workflows[safe: wi]?.localSessionMode ?? .reuseFocused },
                            set: { if wi < workspace.settings.workflows.count { workspace.settings.workflows[wi].localSessionMode = $0 } }
                        )) {
                            ForEach(WorkspaceWorkflowLocalSessionMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }

                        Toggle(localized("settings.workspace.workflow.runSetupScript"), isOn: Binding(
                            get: { workspace.workflows[safe: wi]?.runSetupScript ?? false },
                            set: { if wi < workspace.settings.workflows.count { workspace.settings.workflows[wi].runSetupScript = $0 } }
                        ))

                        Toggle(localized("settings.workspace.workflow.runWorkspaceScript"), isOn: Binding(
                            get: { workspace.workflows[safe: wi]?.runWorkspaceScript ?? false },
                            set: { if wi < workspace.settings.workflows.count { workspace.settings.workflows[wi].runWorkspaceScript = $0 } }
                        ))

                        Picker(localized("settings.workspace.workflow.agentPreset"), selection: Binding(
                            get: { workspace.workflows[safe: wi]?.agentPresetID },
                            set: { if wi < workspace.settings.workflows.count { workspace.settings.workflows[wi].agentPresetID = $0 } }
                        )) {
                            Text(localized("settings.workspace.workflow.noAgent")).tag(Optional<UUID>.none)
                            ForEach(store.appSettings.agentPresets) { preset in
                                Text(preset.name).tag(Optional(preset.id))
                            }
                        }

                        Picker(localized("settings.workspace.workflow.agentLaunch"), selection: Binding(
                            get: { workspace.workflows[safe: wi]?.agentMode ?? .none },
                            set: { if wi < workspace.settings.workflows.count { workspace.settings.workflows[wi].agentMode = $0 } }
                        )) {
                            ForEach(WorkspaceWorkflowAgentMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func commandCard(workspace: WorkspaceModel, wi: Int, ci: Int, commandID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField(
                    localized("settings.workspace.workflow.batchCommand.name"),
                    text: Binding(
                        get: { workspace.workflows[safe: wi]?.commands[safe: ci]?.name ?? "" },
                        set: {
                            if wi < workspace.settings.workflows.count,
                               ci < workspace.settings.workflows[wi].commands.count {
                                workspace.settings.workflows[wi].commands[ci].name = $0
                            }
                        }
                    )
                )
                .frame(maxWidth: 180)

                Picker("", selection: Binding(
                    get: { workspace.workflows[safe: wi]?.commands[safe: ci]?.splitAxis ?? .vertical },
                    set: {
                        if wi < workspace.settings.workflows.count,
                           ci < workspace.settings.workflows[wi].commands.count {
                            workspace.settings.workflows[wi].commands[ci].splitAxis = $0
                        }
                    }
                )) {
                    Text(localized("settings.workflow.batchCommand.splitRight")).tag(PaneSplitAxis.vertical)
                    Text(localized("settings.workflow.batchCommand.splitDown")).tag(PaneSplitAxis.horizontal)
                }
                .frame(maxWidth: 130)

                Spacer()

                Button(role: .destructive) {
                    if wi < workspace.settings.workflows.count {
                        workspace.settings.workflows[wi].commands.removeAll { $0.id == commandID }
                    }
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.borderless)
            }

            TextField(
                localized("settings.workspace.workflow.batchCommand.command"),
                text: Binding(
                    get: { workspace.workflows[safe: wi]?.commands[safe: ci]?.command ?? "" },
                    set: {
                        if wi < workspace.settings.workflows.count,
                           ci < workspace.settings.workflows[wi].commands.count {
                            workspace.settings.workflows[wi].commands[ci].command = $0
                        }
                    }
                )
            )
            .font(.system(size: 12, design: .monospaced))
        }
        .padding(10)
        .background(LineyTheme.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
