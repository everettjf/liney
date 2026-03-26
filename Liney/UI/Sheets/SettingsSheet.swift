//
//  SettingsSheet.swift
//  Liney
//
//  Author: everettjf
//

import SwiftUI

private enum SettingsSheetSection: String, CaseIterable, Identifiable {
    case general
    case sidebar
    case shortcuts
    case updates
    case workspace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .sidebar:
            return "Sidebar"
        case .shortcuts:
            return "Shortcuts"
        case .updates:
            return "Updates"
        case .workspace:
            return "Workspace"
        }
    }

    var subtitle: String {
        switch self {
        case .general:
            return "App behavior and integrations"
        case .sidebar:
            return "Navigation density and default icons"
        case .shortcuts:
            return "Customize Liney app shortcuts"
        case .updates:
            return "Automatic update checks"
        case .workspace:
            return "Per-workspace scripts, presets, and overrides"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "gearshape"
        case .sidebar:
            return "sidebar.leading"
        case .shortcuts:
            return "command"
        case .updates:
            return "arrow.down.circle"
        case .workspace:
            return "square.grid.2x2"
        }
    }
}

struct SettingsSheet: View {
    let request: WorkspaceSettingsRequest

    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss

    @State private var appSettings = AppSettings()
    @State private var selection: SettingsSheetSection = .general
    @State private var selectedWorkspaceID: UUID?
    @State private var workspaceSettings = WorkspaceSettings()

    private var availableExternalEditors: [ExternalEditorDescriptor] {
        store.availableExternalEditors
    }

    private var resolvedExternalEditor: ExternalEditorDescriptor? {
        ExternalEditorCatalog.effectiveEditor(
            preferred: appSettings.preferredExternalEditor,
            among: availableExternalEditors
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsSheetSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .frame(width: 200)

            Divider()

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selection.title)
                        .font(.system(size: 20, weight: .semibold))
                    Text(selection.subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        detailContent
                    }
                    .padding(20)
                }

                Divider()

                HStack {
                    Spacer()
                    Button("Cancel") {
                        dismiss()
                    }
                    Button("Save") {
                        save()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(20)
            }
        }
        .frame(width: 980, height: 720)
        .task(id: request.id) {
            reloadFromStore()
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .general:
            generalSettingsView
        case .sidebar:
            sidebarSettingsView
        case .shortcuts:
            shortcutsSettingsView
        case .updates:
            updatesSettingsView
        case .workspace:
            workspaceSettingsView
        }
    }

    private var generalSettingsView: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox("Behavior") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable automatic refresh", isOn: $appSettings.autoRefreshEnabled)
                    Toggle("Close terminal panes automatically after process exit", isOn: $appSettings.autoClosePaneOnProcessExit)
                    Toggle("Confirm before quitting if commands are still running", isOn: $appSettings.confirmQuitWhenCommandsRunning)
                    Toggle("Enable hot key window", isOn: $appSettings.hotKeyWindowEnabled)
                    Toggle("Enable file watchers", isOn: $appSettings.fileWatcherEnabled)
                    Toggle("Allow system notifications", isOn: $appSettings.systemNotificationsEnabled)
                    Toggle("Show archived workspaces in sidebar", isOn: $appSettings.showArchivedWorkspaces)

                    HStack {
                        Text("Refresh interval")
                        Spacer()
                        TextField("30", value: $appSettings.autoRefreshIntervalSeconds, format: .number)
                            .frame(width: 72)
                            .textFieldStyle(.roundedBorder)
                        Text("seconds")
                            .foregroundStyle(.secondary)
                    }

                }
                .padding(.top, 8)
            }

            GroupBox("Hot Key Window") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("When enabled, the configured global shortcut toggles the main Liney window even while another app is active.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack(alignment: .center, spacing: 12) {
                        Text("Global shortcut")
                        Spacer()
                        ShortcutRecorderField(
                            shortcut: hotKeyWindowShortcutBinding,
                            fallbackShortcut: StoredShortcut(key: " ", command: true, shift: true, option: false, control: false),
                            emptyTitle: "Not Set",
                            displayString: { $0.displayString },
                            transformRecordedShortcut: { $0 }
                        )
                        .frame(width: 132)
                    }

                    Text(appSettings.hotKeyWindowEnabled ? "The window stays available from the global shortcut until you turn this off." : "Disabled by default. Turn it on explicitly if you want iTerm-style summon/hide behavior.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }

            GroupBox("External Editor") {
                VStack(alignment: .leading, spacing: 12) {
                    if availableExternalEditors.isEmpty {
                        Text("Install Cursor, Zed, VS Code, Windsurf, Xcode, Fleet, Nova, or Sublime Text to enable one-click open from the toolbar.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Default editor", selection: $appSettings.preferredExternalEditor) {
                            ForEach(availableExternalEditors) { editor in
                                Text(editor.editor.displayName)
                                    .tag(editor.editor)
                            }
                        }

                        if let resolvedExternalEditor,
                           resolvedExternalEditor.editor != appSettings.preferredExternalEditor {
                            Text("\(appSettings.preferredExternalEditor.displayName) is not installed. Toolbar actions will fall back to \(resolvedExternalEditor.editor.displayName).")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("The toolbar split button uses this editor for one-click open and remembers your choice across launches.")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 8)
            }

            GroupBox("Terminal") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Use custom terminal font size", isOn: terminalFontSizeEnabledBinding)

                    if appSettings.terminalFontSize != nil {
                        HStack {
                            Text("Font size")
                            Spacer()
                            Text("\(Int((appSettings.terminalFontSize ?? 13).rounded())) pt")
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: terminalFontSizeBinding, in: 10...24, step: 1)
                    }

                    Text("Applies to new or restarted terminal sessions. Leave this off to keep Ghostty's default size.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }

            GroupBox("Quick Commands") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Toolbar shortcuts insert reusable command snippets into the focused terminal without running them.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text("\(appSettings.quickCommandPresets.count) commands configured, \(appSettings.quickCommandRecentIDs.count) recent shortcuts remembered.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
        }
    }

    private var sidebarSettingsView: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox("Sidebar") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Show branch or path subtitles", isOn: $appSettings.sidebarShowsSecondaryLabels)
                    Toggle("Show workspace badges", isOn: $appSettings.sidebarShowsWorkspaceBadges)
                    Toggle("Show worktree badges", isOn: $appSettings.sidebarShowsWorktreeBadges)
                }
                .padding(.top, 8)
            }

            GroupBox("Default Icons") {
                VStack(alignment: .leading, spacing: 12) {
                    SidebarIconEditorCard(
                        title: "Repository",
                        subtitle: "Top-level repo workspaces",
                        icon: $appSettings.defaultRepositoryIcon,
                        randomizer: SidebarItemIcon.randomRepository
                    )

                    SidebarIconEditorCard(
                        title: "Terminal",
                        subtitle: "Local shell workspaces",
                        icon: $appSettings.defaultLocalTerminalIcon
                    )

                    SidebarIconEditorCard(
                        title: "Worktree",
                        subtitle: "Shared fallback icon. Leave it at default to auto-randomize rows.",
                        icon: $appSettings.defaultWorktreeIcon,
                        randomizer: SidebarItemIcon.randomRepository
                    )
                }
                .padding(.top, 8)
            }
        }
    }

    private var updatesSettingsView: some View {
        GroupBox("Automatic Updates") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Check for app updates automatically", isOn: $appSettings.autoCheckForUpdates)
                Toggle("Download and install updates automatically", isOn: $appSettings.autoDownloadUpdates)
                    .disabled(!appSettings.autoCheckForUpdates)

                Text("Current app: \(store.currentReleaseVersion)\(store.currentReleaseBuild.map { " (\($0))" } ?? "")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("Signed app updates are delivered through Sparkle.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Button("Check for Updates Now") {
                    store.dispatch(.checkForUpdates)
                }
            }
            .padding(.top, 8)
        }
    }

    private var shortcutsSettingsView: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Liney shortcuts are routed through the app menu so they continue to work while a terminal pane has focus.")
                        .font(.system(size: 12, weight: .medium))
                    Text("When you assign a shortcut to a new action, Liney automatically clears it from the previous action to avoid collisions.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack {
                        Spacer()
                        Button("Reset All to Defaults") {
                            LineyKeyboardShortcuts.resetAll(in: &appSettings)
                        }
                        .disabled(appSettings.keyboardShortcutOverrides.isEmpty)
                    }
                }
                .padding(.top, 8)
            }

            ForEach(LineyShortcutCategory.allCases) { category in
                GroupBox(category.title) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(LineyShortcutAction.allCases.filter { $0.category == category }) { action in
                            ShortcutSettingsRow(
                                action: action,
                                shortcut: shortcutBinding(for: action),
                                state: LineyKeyboardShortcuts.state(for: action, in: appSettings),
                                onReset: { LineyKeyboardShortcuts.resetShortcut(for: action, in: &appSettings) },
                                onDisable: {
                                    if action.defaultShortcut == nil {
                                        LineyKeyboardShortcuts.resetShortcut(for: action, in: &appSettings)
                                    } else {
                                        LineyKeyboardShortcuts.disableShortcut(for: action, in: &appSettings)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    private var workspaceSettingsView: some View {
        GroupBox("Workspace") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Workspace", selection: Binding(
                    get: { selectedWorkspaceID ?? store.selectedWorkspace?.id },
                    set: { newValue in
                        selectedWorkspaceID = newValue
                        loadWorkspaceSettings()
                    }
                )) {
                    ForEach(store.workspaces) { workspace in
                        Text(workspace.name).tag(Optional(workspace.id))
                    }
                }

                if selectedWorkspace != nil {
                    WorkspaceSidebarAppearanceSection(
                        store: store,
                        workspace: selectedWorkspace,
                        appSettings: appSettings,
                        workspaceSettings: $workspaceSettings
                    )

                    Toggle("Pinned in sidebar", isOn: $workspaceSettings.isPinned)
                    Toggle("Archived", isOn: $workspaceSettings.isArchived)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Run script")
                            .font(.system(size: 12, weight: .semibold))
                        TextEditor(text: $workspaceSettings.runScript)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(height: 80)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08)))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Setup script")
                            .font(.system(size: 12, weight: .semibold))
                        TextEditor(text: $workspaceSettings.setupScript)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(height: 80)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08)))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Agent presets")
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Button("Add Preset") {
                                workspaceSettings.agentPresets.append(
                                    AgentPreset(name: "Agent", launchPath: "/usr/bin/env", arguments: ["codex", "resume"])
                                )
                            }
                        }

                        ForEach($workspaceSettings.agentPresets) { $preset in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    TextField("Name", text: $preset.name)
                                    TextField("Launch path", text: $preset.launchPath)
                                    Button(role: .destructive) {
                                        workspaceSettings.agentPresets.removeAll { $0.id == preset.id }
                                        if workspaceSettings.preferredAgentPresetID == preset.id {
                                            workspaceSettings.preferredAgentPresetID = workspaceSettings.agentPresets.first?.id
                                        }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                }

                                TextField(
                                    "Arguments",
                                    text: Binding(
                                        get: { preset.arguments.joined(separator: "\n") },
                                        set: { preset.arguments = $0.split(whereSeparator: \.isNewline).map(String.init) }
                                    ),
                                    axis: .vertical
                                )
                                .lineLimit(2...5)

                                TextField(
                                    "Environment",
                                    text: Binding(
                                        get: {
                                            preset.environment
                                                .sorted { $0.key < $1.key }
                                                .map { "\($0.key)=\($0.value)" }
                                                .joined(separator: "\n")
                                        },
                                        set: { value in
                                            preset.environment = value
                                                .split(whereSeparator: \.isNewline)
                                                .reduce(into: [:]) { result, line in
                                                    let text = String(line)
                                                    guard let index = text.firstIndex(of: "=") else { return }
                                                    let key = String(text[..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
                                                    let envValue = String(text[text.index(after: index)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                                                    guard !key.isEmpty else { return }
                                                    result[key] = envValue
                                                }
                                        }
                                    ),
                                    axis: .vertical
                                )
                                .lineLimit(2...5)
                            }
                            .padding(12)
                            .background(LineyTheme.subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }

                        if !workspaceSettings.agentPresets.isEmpty {
                            Picker("Preferred preset", selection: Binding(
                                get: { workspaceSettings.preferredAgentPresetID ?? workspaceSettings.agentPresets.first?.id },
                                set: { workspaceSettings.preferredAgentPresetID = $0 }
                            )) {
                                ForEach(workspaceSettings.agentPresets) { preset in
                                    Text(preset.name).tag(Optional(preset.id))
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Remote targets")
                                    .font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Button("Add Remote Target") {
                                    workspaceSettings.remoteTargets.append(
                                        RemoteWorkspaceTarget(
                                            name: "Remote",
                                            ssh: SSHSessionConfiguration(
                                                host: "",
                                                user: nil,
                                                port: nil,
                                                identityFilePath: nil,
                                                remoteWorkingDirectory: nil,
                                                remoteCommand: nil
                                            ),
                                            agentPresetID: workspaceSettings.preferredAgentPresetID
                                        )
                                    )
                                }
                            }

                            if workspaceSettings.remoteTargets.isEmpty {
                                Text("Define reusable remote hosts and optionally bind an agent preset for remote execution.")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }

                            ForEach($workspaceSettings.remoteTargets) { $target in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        TextField("Target name", text: $target.name)
                                        TextField("Host", text: $target.ssh.host)
                                        Button(role: .destructive) {
                                            workspaceSettings.remoteTargets.removeAll { $0.id == target.id }
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                    }

                                    HStack {
                                        TextField("User", text: Binding(
                                            get: { target.ssh.user ?? "" },
                                            set: { target.ssh.user = $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
                                        ))
                                        TextField("Port", text: Binding(
                                            get: { target.ssh.port.map(String.init) ?? "" },
                                            set: { target.ssh.port = Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                                        ))
                                        .frame(width: 90)
                                        TextField("Identity file", text: Binding(
                                            get: { target.ssh.identityFilePath ?? "" },
                                            set: { target.ssh.identityFilePath = $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
                                        ))
                                    }

                                    TextField("Remote workspace path", text: Binding(
                                        get: { target.ssh.remoteWorkingDirectory ?? "" },
                                        set: { target.ssh.remoteWorkingDirectory = $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
                                    ))

                                    Picker("Remote agent preset", selection: Binding(
                                        get: { target.agentPresetID },
                                        set: { target.agentPresetID = $0 }
                                    )) {
                                        Text("No remote agent").tag(Optional<UUID>.none)
                                        ForEach(workspaceSettings.agentPresets) { preset in
                                            Text(preset.name).tag(Optional(preset.id))
                                        }
                                    }
                                }
                                .padding(12)
                                .background(LineyTheme.subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Workflows")
                                    .font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Button("Add Workflow") {
                                    workspaceSettings.workflows.append(
                                        WorkspaceWorkflow(
                                            name: "Ship",
                                            localSessionMode: .reuseFocused,
                                            runSetupScript: !workspaceSettings.setupScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                            runWorkspaceScript: !workspaceSettings.runScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                            agentPresetID: workspaceSettings.preferredAgentPresetID ?? workspaceSettings.agentPresets.first?.id,
                                            agentMode: workspaceSettings.agentPresets.isEmpty ? .none : .splitRight
                                        )
                                    )
                                }
                            }

                            if workspaceSettings.workflows.isEmpty {
                                Text("Create reusable playbooks that chain setup, run, and agent launch.")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }

                            ForEach($workspaceSettings.workflows) { $workflow in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        TextField("Workflow name", text: $workflow.name)
                                        Button(role: .destructive) {
                                            workspaceSettings.workflows.removeAll { $0.id == workflow.id }
                                            if workspaceSettings.preferredWorkflowID == workflow.id {
                                                workspaceSettings.preferredWorkflowID = workspaceSettings.workflows.first?.id
                                            }
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                    }

                                    Picker("Local shell", selection: $workflow.localSessionMode) {
                                        ForEach(WorkspaceWorkflowLocalSessionMode.allCases) { mode in
                                            Text(mode.title).tag(mode)
                                        }
                                    }

                                    Toggle("Run setup script", isOn: $workflow.runSetupScript)
                                    Toggle("Run workspace script", isOn: $workflow.runWorkspaceScript)

                                    Picker("Agent preset", selection: Binding(
                                        get: { workflow.agentPresetID },
                                        set: { workflow.agentPresetID = $0 }
                                    )) {
                                        Text("No agent").tag(Optional<UUID>.none)
                                        ForEach(workspaceSettings.agentPresets) { preset in
                                            Text(preset.name).tag(Optional(preset.id))
                                        }
                                    }

                                    Picker("Agent launch", selection: $workflow.agentMode) {
                                        ForEach(WorkspaceWorkflowAgentMode.allCases) { mode in
                                            Text(mode.title).tag(mode)
                                        }
                                    }
                                }
                                .padding(12)
                                .background(LineyTheme.subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }

                            if !workspaceSettings.workflows.isEmpty {
                                Picker("Preferred workflow", selection: Binding(
                                    get: { workspaceSettings.preferredWorkflowID ?? workspaceSettings.workflows.first?.id },
                                    set: { workspaceSettings.preferredWorkflowID = $0 }
                                )) {
                                    ForEach(workspaceSettings.workflows) { workflow in
                                        Text(workflow.name).tag(Optional(workflow.id))
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Text("Select a workspace to edit repository-specific settings.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
        }
    }

    private var selectedWorkspace: WorkspaceModel? {
        guard let selectedWorkspaceID else { return nil }
        return store.workspaces.first(where: { $0.id == selectedWorkspaceID })
    }

    private func loadWorkspaceSettings() {
        if let selectedWorkspace {
            workspaceSettings = selectedWorkspace.settings
        } else {
            workspaceSettings = WorkspaceSettings()
        }
    }

    private func reloadFromStore() {
        appSettings = store.appSettings
        selectedWorkspaceID = request.workspaceID ?? store.selectedWorkspace?.id
        loadWorkspaceSettings()
    }

    private func save() {
        appSettings.autoRefreshIntervalSeconds = max(10, appSettings.autoRefreshIntervalSeconds)
        appSettings.keyboardShortcutOverrides = LineyKeyboardShortcuts.normalizedOverrides(appSettings.keyboardShortcutOverrides)
        store.updateAppSettings(appSettings)

        if let selectedWorkspaceID {
            store.updateWorkspaceSettings(workspaceID: selectedWorkspaceID, settings: workspaceSettings)
        }
        dismiss()
    }

    private func shortcutBinding(for action: LineyShortcutAction) -> Binding<StoredShortcut?> {
        Binding(
            get: { LineyKeyboardShortcuts.effectiveShortcut(for: action, in: appSettings) },
            set: { newShortcut in
                guard let newShortcut else {
                    if action.defaultShortcut == nil {
                        LineyKeyboardShortcuts.resetShortcut(for: action, in: &appSettings)
                    } else {
                        LineyKeyboardShortcuts.disableShortcut(for: action, in: &appSettings)
                    }
                    return
                }
                LineyKeyboardShortcuts.setShortcut(newShortcut, for: action, in: &appSettings)
            }
        )
    }

    private var hotKeyWindowShortcutBinding: Binding<StoredShortcut?> {
        Binding(
            get: { appSettings.hotKeyWindowShortcut },
            set: { newShortcut in
                guard let newShortcut else { return }
                appSettings.hotKeyWindowShortcut = newShortcut
            }
        )
    }

    private var terminalFontSizeEnabledBinding: Binding<Bool> {
        Binding(
            get: { appSettings.terminalFontSize != nil },
            set: { enabled in
                if enabled {
                    appSettings.terminalFontSize = appSettings.terminalFontSize ?? 13
                } else {
                    appSettings.terminalFontSize = nil
                }
            }
        )
    }

    private var terminalFontSizeBinding: Binding<Double> {
        Binding(
            get: { appSettings.terminalFontSize ?? 13 },
            set: { appSettings.terminalFontSize = min(max($0, 10), 24) }
        )
    }
}

private struct WorkspaceSidebarAppearanceSection: View {
    let store: WorkspaceStore
    let workspace: WorkspaceModel?
    let appSettings: AppSettings
    @Binding var workspaceSettings: WorkspaceSettings

    private var workspaceIconFallback: SidebarItemIcon {
        guard let workspace else { return .repositoryDefault }
        return workspace.supportsRepositoryFeatures ? appSettings.defaultRepositoryIcon : appSettings.defaultLocalTerminalIcon
    }

    private var workspaceIconBinding: Binding<SidebarItemIcon> {
        Binding(
            get: { workspaceSettings.workspaceIcon ?? workspaceIconFallback },
            set: { workspaceSettings.workspaceIcon = $0 }
        )
    }

    private var workspaceIconRandomizer: () -> SidebarItemIcon {
        guard let workspace, workspace.supportsRepositoryFeatures else {
            return SidebarItemIcon.random
        }
        return SidebarItemIcon.randomRepository
    }

    private var activeWorktree: WorktreeModel? {
        workspace?.activeWorktree
    }

    private var activeWorktreeIconBinding: Binding<SidebarItemIcon> {
        Binding(
            get: {
                guard let activeWorktree else { return appSettings.defaultWorktreeIcon }
                if let override = workspaceSettings.worktreeIconOverrides[activeWorktree.path] {
                    return override
                }
                guard let workspace else { return appSettings.defaultWorktreeIcon }
                return store.sidebarIcon(for: activeWorktree, in: workspace)
            },
            set: { updated in
                guard let activeWorktree else { return }
                workspaceSettings.worktreeIconOverrides[activeWorktree.path] = updated
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sidebar appearance")
                .font(.system(size: 12, weight: .semibold))

            Toggle(
                "Use custom workspace icon",
                isOn: Binding(
                    get: { workspaceSettings.workspaceIcon != nil },
                    set: { isEnabled in
                        workspaceSettings.workspaceIcon = isEnabled ? workspaceIconFallback : nil
                    }
                )
            )

            if workspaceSettings.workspaceIcon != nil {
                SidebarIconEditorCard(
                    title: "Workspace icon",
                    subtitle: "Overrides the app default for this workspace",
                    icon: workspaceIconBinding,
                    randomizer: workspaceIconRandomizer
                )
            }

            if let activeWorktree {
                Toggle(
                    "Use custom icon for active worktree (\(activeWorktree.displayName))",
                    isOn: Binding(
                        get: { workspaceSettings.worktreeIconOverrides[activeWorktree.path] != nil },
                        set: { isEnabled in
                            if isEnabled {
                                let icon = workspace.map { store.sidebarIcon(for: activeWorktree, in: $0) } ?? appSettings.defaultWorktreeIcon
                                workspaceSettings.worktreeIconOverrides[activeWorktree.path] = icon
                            } else {
                                workspaceSettings.worktreeIconOverrides[activeWorktree.path] = nil
                            }
                        }
                    )
                )

                if workspaceSettings.worktreeIconOverrides[activeWorktree.path] != nil {
                    SidebarIconEditorCard(
                        title: "Active worktree icon",
                        subtitle: "For other branches, use the sidebar context menu",
                        icon: activeWorktreeIconBinding,
                        randomizer: SidebarItemIcon.randomRepository
                    )
                }

                if workspaceSettings.worktreeIconOverrides.count > 0 {
                    Text("\(workspaceSettings.worktreeIconOverrides.count) worktree icon overrides configured")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(LineyTheme.subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct SidebarIconEditorCard: View {
    let title: String
    let subtitle: String?
    @Binding var icon: SidebarItemIcon
    var randomizer: () -> SidebarItemIcon = SidebarItemIcon.random

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                SidebarItemIconView(icon: icon, size: 26)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("Random") {
                    icon = randomizer()
                }
            }

            Picker("Symbol", selection: $icon.symbolName) {
                ForEach(SidebarIconCatalog.symbols, id: \.systemName) { symbol in
                    Label(symbol.title, systemImage: symbol.systemName).tag(symbol.systemName)
                }
            }

            Picker("Style", selection: $icon.fillStyle) {
                ForEach(SidebarIconFillStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 8) {
                Text("Palette")
                    .font(.system(size: 11, weight: .semibold))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 34), spacing: 8)], spacing: 8) {
                    ForEach(SidebarIconPalette.allCases) { palette in
                        Button {
                            icon.palette = palette
                        } label: {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [palette.descriptor.gradientStart, palette.descriptor.gradientEnd],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(icon.palette == palette ? Color.white.opacity(0.9) : palette.descriptor.border, lineWidth: icon.palette == palette ? 2 : 1)
                                )
                                .frame(width: 34, height: 24)
                        }
                        .buttonStyle(.plain)
                        .help(palette.title)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ShortcutSettingsRow: View {
    let action: LineyShortcutAction
    @Binding var shortcut: StoredShortcut?
    let state: LineyKeyboardShortcutState
    let onReset: () -> Void
    let onDisable: () -> Void

    private var stateLabel: String {
        switch state {
        case .default:
            return action.defaultShortcut == nil ? "Unset" : "Default"
        case .custom:
            return "Custom"
        case .disabled:
            return "Disabled"
        }
    }

    private var disableButtonTitle: String {
        action.defaultShortcut == nil ? "Clear" : "Disable"
    }

    private var canDisable: Bool {
        if action.defaultShortcut == nil {
            return shortcut != nil
        }
        return state != .disabled
    }

    private var canReset: Bool {
        state != .default
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(action.title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(stateLabel)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.06), in: Capsule())
                }

                Text(action.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            ShortcutRecorderField(
                shortcut: $shortcut,
                fallbackShortcut: action.defaultShortcut ?? StoredShortcut(key: "k", command: true, shift: false, option: false, control: false),
                emptyTitle: "Not Set",
                displayString: { action.displayedShortcutString(for: $0) },
                transformRecordedShortcut: action.normalizedRecordedShortcut
            )
            .frame(width: 132)

            Button(disableButtonTitle, action: onDisable)
                .disabled(!canDisable)

            Button("Reset", action: onReset)
                .disabled(!canReset)
        }
        .padding(.vertical, 2)
    }
}

private struct ShortcutRecorderField: NSViewRepresentable {
    @Binding var shortcut: StoredShortcut?
    let fallbackShortcut: StoredShortcut
    let emptyTitle: String
    let displayString: (StoredShortcut) -> String
    let transformRecordedShortcut: (StoredShortcut) -> StoredShortcut?

    func makeNSView(context: Context) -> ShortcutRecorderNSButton {
        let button = ShortcutRecorderNSButton()
        button.shortcut = shortcut
        button.fallbackShortcut = fallbackShortcut
        button.emptyTitle = emptyTitle
        button.displayString = displayString
        button.transformRecordedShortcut = transformRecordedShortcut
        button.onShortcutRecorded = { newShortcut in
            shortcut = newShortcut
        }
        return button
    }

    func updateNSView(_ nsView: ShortcutRecorderNSButton, context: Context) {
        nsView.shortcut = shortcut
        nsView.fallbackShortcut = fallbackShortcut
        nsView.emptyTitle = emptyTitle
        nsView.displayString = displayString
        nsView.transformRecordedShortcut = transformRecordedShortcut
        nsView.updateTitle()
    }
}

private final class ShortcutRecorderNSButton: NSButton {
    var shortcut: StoredShortcut?
    var fallbackShortcut = StoredShortcut(key: "k", command: true, shift: false, option: false, control: false)
    var emptyTitle = "Not Set"
    var displayString: (StoredShortcut) -> String = { $0.displayString }
    var transformRecordedShortcut: (StoredShortcut) -> StoredShortcut? = { $0 }
    var onShortcutRecorded: ((StoredShortcut) -> Void)?

    private var isRecording = false
    private var eventMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(buttonClicked)
        updateTitle()
    }

    func updateTitle() {
        if isRecording {
            title = "Press shortcut…"
        } else if let shortcut {
            title = displayString(shortcut)
        } else {
            title = emptyTitle
        }
    }

    @objc private func buttonClicked() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        updateTitle()

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            if event.keyCode == 53 {
                self.stopRecording()
                return nil
            }

            if let newShortcut = StoredShortcut.from(event: event) {
                guard let transformedShortcut = self.transformRecordedShortcut(newShortcut) else {
                    NSSound.beep()
                    return nil
                }
                self.shortcut = transformedShortcut
                self.onShortcutRecorded?(transformedShortcut)
                self.stopRecording()
                return nil
            }

            return nil
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowResigned),
            name: NSWindow.didResignKeyNotification,
            object: window
        )
    }

    private func stopRecording() {
        isRecording = false
        updateTitle()

        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }

        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window)
    }

    @objc private func windowResigned() {
        stopRecording()
    }

    deinit {
        stopRecording()
    }
}

struct SidebarIconCustomizationSheet: View {
    let request: SidebarIconCustomizationRequest

    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss

    @State private var icon = SidebarItemIcon.repositoryDefault

    private var title: String {
        store.sidebarIconRequestTitle(request)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Customize Sidebar Icon")
                .font(.system(size: 20, weight: .semibold))

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            SidebarIconEditorCard(
                title: "Icon",
                subtitle: "Choose a symbol, palette, and fill treatment",
                icon: $icon,
                randomizer: randomizer
            )

            HStack {
                Spacer()
                if resetSupported {
                    Button("Reset") {
                        store.resetSidebarIcon(for: request.target)
                        dismiss()
                    }
                }
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    store.updateSidebarIcon(icon, for: request.target)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 480)
        .task {
            icon = store.sidebarIconSelection(for: request.target)
        }
    }

    private var resetSupported: Bool {
        true
    }

    private var randomizer: () -> SidebarItemIcon {
        switch request.target {
        case .workspace(let workspaceID):
            if store.workspaces.first(where: { $0.id == workspaceID })?.supportsRepositoryFeatures == true {
                return SidebarItemIcon.randomRepository
            }
            return SidebarItemIcon.random
        case .appDefaultRepository:
            return SidebarItemIcon.randomRepository
        case .worktree, .appDefaultWorktree:
            return SidebarItemIcon.randomRepository
        case .appDefaultLocalTerminal:
            return SidebarItemIcon.random
        }
    }
}
