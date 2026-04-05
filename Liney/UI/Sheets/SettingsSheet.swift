//
//  SettingsSheet.swift
//  Liney
//
//  Author: everettjf
//

import AppKit
import SwiftUI

private enum SettingsSidebarGroup: String, CaseIterable, Identifiable {
    case app
    case customize
    case workspace

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .app:
            return "settings.sidebarGroup.app"
        case .customize:
            return "settings.sidebarGroup.customize"
        case .workspace:
            return "settings.sidebarGroup.workspace"
        }
    }
}

private enum SettingsSheetSection: String, CaseIterable, Identifiable {
    case general
    case hotKeyWindow
    case externalEditor
    case terminal
    case sidebar
    case dynamicIsland
    case shortcuts
    case updates
    case workspace
    case sshPresets
    case agentPresets

    var id: String { rawValue }

    var group: SettingsSidebarGroup {
        switch self {
        case .general, .hotKeyWindow, .externalEditor, .terminal, .updates:
            return .app
        case .sidebar, .dynamicIsland, .shortcuts:
            return .customize
        case .workspace, .sshPresets, .agentPresets:
            return .workspace
        }
    }

    var titleKey: String {
        switch self {
        case .general:
            return "settings.section.general.title"
        case .hotKeyWindow:
            return "settings.section.hotKeyWindow.title"
        case .externalEditor:
            return "settings.section.externalEditor.title"
        case .terminal:
            return "settings.section.terminal.title"
        case .sidebar:
            return "settings.section.sidebar.title"
        case .dynamicIsland:
            return "settings.section.dynamicIsland.title"
        case .shortcuts:
            return "settings.section.shortcuts.title"
        case .updates:
            return "settings.section.updates.title"
        case .workspace:
            return "settings.section.workspace.title"
        case .sshPresets:
            return "settings.section.sshPresets.title"
        case .agentPresets:
            return "settings.section.agentPresets.title"
        }
    }

    var subtitleKey: String {
        switch self {
        case .general:
            return "settings.section.general.subtitle"
        case .hotKeyWindow:
            return "settings.section.hotKeyWindow.subtitle"
        case .externalEditor:
            return "settings.section.externalEditor.subtitle"
        case .terminal:
            return "settings.section.terminal.subtitle"
        case .sidebar:
            return "settings.section.sidebar.subtitle"
        case .dynamicIsland:
            return "settings.section.dynamicIsland.subtitle"
        case .shortcuts:
            return "settings.section.shortcuts.subtitle"
        case .updates:
            return "settings.section.updates.subtitle"
        case .workspace:
            return "settings.section.workspace.subtitle"
        case .sshPresets:
            return "settings.section.sshPresets.subtitle"
        case .agentPresets:
            return "settings.section.agentPresets.subtitle"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "gearshape"
        case .hotKeyWindow:
            return "macwindow.badge.plus"
        case .externalEditor:
            return "square.and.arrow.up"
        case .terminal:
            return "terminal"
        case .sidebar:
            return "sidebar.leading"
        case .dynamicIsland:
            return "sparkle.magnifyingglass"
        case .shortcuts:
            return "command"
        case .updates:
            return "arrow.down.circle"
        case .workspace:
            return "square.grid.2x2"
        case .sshPresets:
            return "network"
        case .agentPresets:
            return "person.crop.rectangle.stack"
        }
    }
}

private enum LineyTerminalFontCatalog {
    static let defaultVisibleCount = 50

    private static let prioritizedFamilies = [
        "SF Mono",
        "Menlo",
        "Monaco",
        "JetBrains Mono",
        "CommitMono",
        "Cascadia Code",
        "Cascadia Mono",
        "Fira Code",
        "Source Code Pro",
        "IBM Plex Mono",
    ]

    static func availableFamilies(
        fontManager: NSFontManager = .shared,
        limit: Int? = nil
    ) -> [String] {
        let sortedFamilies = fontManager.availableFontFamilies
            .filter { !$0.hasPrefix(".") }
            .sorted { lhs, rhs in
            let leftFixedPitch = isTerminalFriendlyFamily(lhs, fontManager: fontManager)
            let rightFixedPitch = isTerminalFriendlyFamily(rhs, fontManager: fontManager)
            if leftFixedPitch != rightFixedPitch {
                return leftFixedPitch && !rightFixedPitch
            }

            let leftPriority = prioritizedFamilies.firstIndex(of: lhs) ?? .max
            let rightPriority = prioritizedFamilies.firstIndex(of: rhs) ?? .max
            if leftPriority != rightPriority {
                return leftPriority < rightPriority
            }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }

        guard let limit else { return sortedFamilies }
        return Array(sortedFamilies.prefix(limit))
    }

    static func previewFont(
        family: String?,
        size: CGFloat,
        fontManager: NSFontManager = .shared
    ) -> NSFont {
        if let family,
           let font = fontManager.font(
                withFamily: family,
                traits: .fixedPitchFontMask,
                weight: 5,
                size: size
           ) {
            return font
        }

        return .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private static func isTerminalFriendlyFamily(
        _ family: String,
        fontManager: NSFontManager
    ) -> Bool {
        if let members = fontManager.availableMembers(ofFontFamily: family) {
            for member in members {
                guard let fontName = member.first as? String,
                      let font = NSFont(name: fontName, size: 13) else {
                    continue
                }
                if font.isFixedPitch {
                    return true
                }
            }
        }

        if let font = fontManager.font(
            withFamily: family,
            traits: .fixedPitchFontMask,
            weight: 5,
            size: 13
        ) {
            return font.isFixedPitch
        }

        return false
    }
}

struct SettingsSheet: View {
    let request: WorkspaceSettingsRequest

    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss

    @State private var appSettings = AppSettings()
    @State private var selection: SettingsSheetSection = .general
    @State private var selectedWorkspaceID: UUID?
    @State private var terminalFontSearchText = ""
    @State private var workspaceSettings = WorkspaceSettings()
    @State private var localizationVersion = 0
    @State private var originalAppLanguage: AppLanguage = .automatic

    private var availableExternalEditors: [ExternalEditorDescriptor] {
        store.availableExternalEditors
    }

    private var resolvedExternalEditor: ExternalEditorDescriptor? {
        ExternalEditorCatalog.effectiveEditor(
            preferred: appSettings.preferredExternalEditor,
            among: availableExternalEditors
        )
    }

    private func localized(_ key: String) -> String {
        LocalizationManager.shared.string(key)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        l10nFormat(localized(key), locale: Locale.current, arguments: arguments)
    }

    private var allTerminalFontFamilies: [String] {
        LineyTerminalFontCatalog.availableFamilies(limit: nil)
    }

    private var terminalFontFamilies: [String] {
        let availableFamilies = LineyTerminalFontCatalog.availableFamilies(
            limit: LineyTerminalFontCatalog.defaultVisibleCount
        )
        guard let selectedFamily = appSettings.terminalFontFamily,
              !selectedFamily.isEmpty,
              !availableFamilies.contains(selectedFamily) else {
            return availableFamilies
        }
        return [selectedFamily] + availableFamilies
    }

    private var filteredTerminalFontFamilies: [String] {
        let query = terminalFontSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return terminalFontFamilies }
        let filtered = allTerminalFontFamilies.filter { family in
            family.localizedCaseInsensitiveContains(query)
        }
        guard let selectedFamily = appSettings.terminalFontFamily,
              !selectedFamily.isEmpty,
              !filtered.contains(selectedFamily) else {
            return filtered
        }
        return [selectedFamily] + filtered
    }

    private var terminalFontSummaryCount: Int {
        let query = terminalFontSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? min(allTerminalFontFamilies.count, LineyTerminalFontCatalog.defaultVisibleCount) : filteredTerminalFontFamilies.count
    }

    var body: some View {
        let _ = localizationVersion

        HStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(SettingsSidebarGroup.allCases) { group in
                    Section(localized(group.titleKey)) {
                        ForEach(SettingsSheetSection.allCases.filter { $0.group == group }) { section in
                            SettingsNavigationRow(
                                title: localized(section.titleKey),
                                systemImage: section.systemImage
                            )
                            .tag(section)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(width: 230)

            Divider()

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localized(selection.titleKey))
                        .font(.system(size: 20, weight: .semibold))
                    Text(localized(selection.subtitleKey))
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }

                Divider()

                HStack {
                    Spacer()
                    Button {
                        LocalizationManager.shared.updateSelectedLanguage(originalAppLanguage)
                        dismiss()
                    } label: {
                        Label(localized("settings.button.cancel"), systemImage: "xmark")
                    }
                    Button {
                        save()
                    } label: {
                        Label(localized("settings.button.save"), systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(20)
            }
        }
        .frame(width: 1120, height: 760)
        .task(id: request.id) {
            reloadFromStore()
        }
        .onChange(of: appSettings.appLanguage) { _, newLanguage in
            LocalizationManager.shared.updateSelectedLanguage(newLanguage)
        }
        .onReceive(NotificationCenter.default.publisher(for: .lineyLocalizationDidChange)) { _ in
            localizationVersion += 1
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .general:
            generalSettingsView
        case .hotKeyWindow:
            hotKeyWindowSettingsView
        case .externalEditor:
            externalEditorSettingsView
        case .terminal:
            terminalSettingsView
        case .sidebar:
            sidebarSettingsView
        case .dynamicIsland:
            dynamicIslandSettingsView
        case .shortcuts:
            shortcutsSettingsView
        case .updates:
            updatesSettingsView
        case .workspace:
            workspaceSettingsView
        case .sshPresets:
            sshPresetsSettingsView
        case .agentPresets:
            agentPresetsSettingsView
        }
    }

    private var generalSettingsView: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox(localized("settings.general.language.group")) {
                VStack(alignment: .leading, spacing: 12) {
                    Picker(localized("settings.general.language.title"), selection: $appSettings.appLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName)
                                .tag(language)
                        }
                    }

                    Text(localized("settings.general.language.appliesImmediately"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text(localized("settings.general.language.fallback"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }

            GroupBox(localized("settings.general.behavior.group")) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(localized("settings.general.behavior.autoRefresh"), isOn: $appSettings.autoRefreshEnabled)
                    Toggle(localized("settings.general.behavior.autoClosePaneOnExit"), isOn: $appSettings.autoClosePaneOnProcessExit)
                    Toggle(localized("settings.general.behavior.confirmQuitRunningCommands"), isOn: $appSettings.confirmQuitWhenCommandsRunning)
                    Toggle(localized("settings.general.behavior.enableHotKeyWindow"), isOn: $appSettings.hotKeyWindowEnabled)
                    Toggle(localized("settings.general.behavior.enableFileWatchers"), isOn: $appSettings.fileWatcherEnabled)
                    Toggle(localized("settings.general.behavior.allowSystemNotifications"), isOn: $appSettings.systemNotificationsEnabled)
                    Toggle(localized("settings.general.behavior.showArchivedWorkspaces"), isOn: $appSettings.showArchivedWorkspaces)
                    Toggle(localized("settings.general.behavior.showHAPIToolbarButton"), isOn: $appSettings.showHAPIToolbarButton)

                    Divider()

                    HStack {
                        Text(localized("settings.general.behavior.uiScale"))
                        Spacer()
                        Text(localizedFormat("settings.general.behavior.uiScalePercentFormat", Int((appSettings.uiScale * 100).rounded())))
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $appSettings.uiScale, in: 0.85...1.5, step: 0.05)

                    Text(localized("settings.general.behavior.uiScaleHint"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack {
                        Text(localized("settings.general.behavior.refreshInterval"))
                        Spacer()
                        TextField("30", value: $appSettings.autoRefreshIntervalSeconds, format: .number)
                            .frame(width: 72)
                            .textFieldStyle(.roundedBorder)
                        Text(localized("settings.general.behavior.seconds"))
                            .foregroundStyle(.secondary)
                    }

                    Text(localized("settings.general.behavior.refreshIntervalHint"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
        }
    }

    private var hotKeyWindowSettingsView: some View {
        GroupBox(localized("settings.general.hotKeyWindow.group")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(localized("settings.general.hotKeyWindow.description"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(alignment: .center, spacing: 12) {
                    Text(localized("settings.general.hotKeyWindow.globalShortcut"))
                    Spacer()
                    ShortcutRecorderField(
                        shortcut: hotKeyWindowShortcutBinding,
                        fallbackShortcut: StoredShortcut(key: " ", command: true, shift: true, option: false, control: false),
                        emptyTitle: localized("settings.general.hotKeyWindow.notSet"),
                        displayString: { $0.displayString },
                        transformRecordedShortcut: { $0 }
                    )
                    .frame(width: 132)
                }

                Text(appSettings.hotKeyWindowEnabled ? localized("settings.general.hotKeyWindow.enabledHint") : localized("settings.general.hotKeyWindow.disabledHint"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
    }

    private var externalEditorSettingsView: some View {
        GroupBox(localized("settings.general.externalEditor.group")) {
            VStack(alignment: .leading, spacing: 12) {
                if availableExternalEditors.isEmpty {
                    Text(localized("settings.general.externalEditor.installHint"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    Picker(localized("settings.general.externalEditor.defaultEditor"), selection: $appSettings.preferredExternalEditor) {
                        ForEach(availableExternalEditors) { editor in
                            Text(editor.editor.displayName)
                                .tag(editor.editor)
                        }
                    }

                    if let resolvedExternalEditor,
                       resolvedExternalEditor.editor != appSettings.preferredExternalEditor {
                        Text(
                            localizedFormat(
                                "settings.general.externalEditor.fallbackFormat",
                                appSettings.preferredExternalEditor.displayName,
                                resolvedExternalEditor.editor.displayName
                            )
                        )
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(localized("settings.general.externalEditor.activeHint"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    private var terminalSettingsView: some View {
        HStack(alignment: .top, spacing: 20) {
            GroupBox(localized("settings.general.terminal.group")) {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(localized("settings.general.terminal.useCustomTheme"), isOn: terminalThemeEnabledBinding)

                    if appSettings.terminalTheme != nil {
                        TextField(
                            localized("settings.general.terminal.themeName"),
                            text: terminalThemeBinding
                        )
                        .textFieldStyle(.roundedBorder)

                        Text(localized("settings.general.terminal.themeHint"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    Toggle(localized("settings.general.terminal.useCustomFont"), isOn: terminalFontFamilyEnabledBinding)

                    if appSettings.terminalFontFamily != nil {
                        if terminalFontFamilies.isEmpty {
                            Text(localized("settings.general.terminal.fontUnavailable"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        } else {
                            TextField(
                                localized("settings.general.terminal.font"),
                                text: terminalFontFamilyBinding
                            )
                            .textFieldStyle(.roundedBorder)

                            TextField(
                                localized("settings.general.terminal.fontSearchPlaceholder"),
                                text: $terminalFontSearchText
                            )
                            .textFieldStyle(.roundedBorder)

                            Text(
                                localizedFormat(
                                    "settings.general.terminal.availableFontsFormat",
                                    terminalFontSummaryCount,
                                    allTerminalFontFamilies.count
                                )
                            )
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)

                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 8) {
                                    ForEach(filteredTerminalFontFamilies, id: \.self) { family in
                                        TerminalFontOptionRow(
                                            family: family,
                                            isSelected: terminalFontFamilyBinding.wrappedValue == family
                                        ) {
                                            terminalFontFamilyBinding.wrappedValue = family
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            .frame(height: 240)

                            if filteredTerminalFontFamilies.isEmpty {
                                Text(localized("settings.general.terminal.noSearchResults"))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(localized("settings.general.terminal.fontHint"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    Toggle(localized("settings.general.terminal.useCustomFontSize"), isOn: terminalFontSizeEnabledBinding)

                    HStack {
                        Text(localized("settings.general.terminal.fontSize"))
                        Spacer()
                        Text("\(Int((appSettings.terminalFontSize ?? 13).rounded())) pt")
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: terminalFontSizeBinding, in: 10...24, step: 1)
                        .disabled(appSettings.terminalFontSize == nil)

                    Text(localized("settings.general.terminal.fontSizeHint"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: 420, alignment: .topLeading)

            TerminalFontPreviewCard(
                title: localized("settings.general.terminal.previewTitle"),
                subtitle: localized("settings.general.terminal.previewSubtitle"),
                family: appSettings.terminalFontFamily,
                usesCustomFamily: appSettings.terminalFontFamily != nil,
                size: appSettings.terminalFontSize ?? 13,
                usesCustomSize: appSettings.terminalFontSize != nil,
                defaultFamilyLabel: localized("settings.general.terminal.defaultFontLabel"),
                customSizeFormat: localized("settings.general.terminal.customSizeFormat"),
                defaultSizeFormat: localized("settings.general.terminal.defaultSizeFormat")
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var dynamicIslandSettingsView: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Toggle(localized("settings.dynamicIsland.enable.toggle"), isOn: $appSettings.dynamicIslandEnabled)
                        Text("Beta")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(.orange))
                    }
                    Text(localized("settings.dynamicIsland.enable.description"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } label: {
                Text(localized("settings.dynamicIsland.enable.group"))
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Picker(localized("settings.dynamicIsland.width"), selection: $appSettings.dynamicIslandWidth) {
                        ForEach(IslandWidthPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker(localized("settings.dynamicIsland.height"), selection: $appSettings.dynamicIslandHeight) {
                        ForEach(IslandHeightPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Pixel Animation", selection: $appSettings.dynamicIslandPixelAnimation) {
                        ForEach(IslandPixelAnimationStyle.allCases, id: \.self) { style in
                            Label(style.displayName, systemImage: style.iconName)
                                .tag(style)
                        }
                    }
                    .pickerStyle(.menu)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Preview")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        IslandPixelAnimationPreview(style: appSettings.dynamicIslandPixelAnimation, previewHeight: appSettings.dynamicIslandHeight.collapsedHeight)
                            .frame(width: appSettings.dynamicIslandWidth.collapsedMaxWidth)
                            .id(appSettings.dynamicIslandPixelAnimation)
                    }
                }
            } label: {
                Text(localized("settings.dynamicIsland.size.group"))
            }
        }
    }

    private var sidebarSettingsView: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox(localized("settings.sidebar.visibility.group")) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(localized("settings.sidebar.visibility.showSecondaryLabels"), isOn: $appSettings.sidebarShowsSecondaryLabels)
                    Toggle(localized("settings.sidebar.visibility.showWorkspaceBadges"), isOn: $appSettings.sidebarShowsWorkspaceBadges)
                    Toggle(localized("settings.sidebar.visibility.showWorktreeBadges"), isOn: $appSettings.sidebarShowsWorktreeBadges)
                }
                .padding(.top, 8)
            }

            GroupBox(localized("settings.sidebar.activity.group")) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker(localized("settings.sidebar.activity.color"), selection: $appSettings.sidebarActivityIndicatorPalette) {
                        ForEach(SidebarIconPalette.allCases) { palette in
                            Text(palette.title).tag(palette)
                        }
                    }

                    Text(localized("settings.sidebar.activity.hint"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }

            GroupBox(localized("settings.sidebar.defaultIcons.group")) {
                VStack(alignment: .leading, spacing: 12) {
                    SidebarIconEditorCard(
                        title: localized("settings.sidebar.defaultIcons.repository.title"),
                        subtitle: localized("settings.sidebar.defaultIcons.repository.subtitle"),
                        icon: $appSettings.defaultRepositoryIcon,
                        randomizer: SidebarItemIcon.randomRepository
                    )

                    SidebarIconEditorCard(
                        title: localized("settings.sidebar.defaultIcons.terminal.title"),
                        subtitle: localized("settings.sidebar.defaultIcons.terminal.subtitle"),
                        icon: $appSettings.defaultLocalTerminalIcon
                    )

                    SidebarIconEditorCard(
                        title: localized("settings.sidebar.defaultIcons.worktree.title"),
                        subtitle: localized("settings.sidebar.defaultIcons.worktree.subtitle"),
                        icon: $appSettings.defaultWorktreeIcon,
                        randomizer: SidebarItemIcon.randomRepository
                    )
                }
                .padding(.top, 8)
            }
        }
    }

    private var updatesSettingsView: some View {
        GroupBox(localized("settings.updates.group")) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(localized("settings.updates.autoCheck"), isOn: $appSettings.autoCheckForUpdates)
                Toggle(localized("settings.updates.autoDownload"), isOn: $appSettings.autoDownloadUpdates)
                    .disabled(!appSettings.autoCheckForUpdates)

                Text(
                    localizedFormat(
                        "settings.updates.currentAppFormat",
                        store.currentReleaseVersion,
                        store.currentReleaseBuild.map { " (\($0))" } ?? ""
                    )
                )
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(localized("settings.updates.sparkleHint"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Button(localized("settings.updates.checkNow")) {
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
                    Text(localized("settings.shortcuts.intro"))
                        .font(.system(size: 12, weight: .medium))
                    Text(localized("settings.shortcuts.conflictHint"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack {
                        Spacer()
                        Button(localized("settings.shortcuts.resetAll")) {
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
        GroupBox(localized("settings.workspace.group")) {
            VStack(alignment: .leading, spacing: 12) {
                Picker(localized("settings.workspace.selector"), selection: Binding(
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

                    Toggle(localized("settings.workspace.pinned"), isOn: $workspaceSettings.isPinned)
                    Toggle(localized("settings.workspace.archived"), isOn: $workspaceSettings.isArchived)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(localized("settings.workspace.runScript"))
                            .font(.system(size: 12, weight: .semibold))
                        TextEditor(text: $workspaceSettings.runScript)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(height: 80)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08)))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(localized("settings.workspace.setupScript"))
                            .font(.system(size: 12, weight: .semibold))
                        TextEditor(text: $workspaceSettings.setupScript)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(height: 80)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08)))
                    }
                } else {
                    Text(localized("settings.workspace.emptyState"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
        }
    }

    private var agentPresetsSettingsView: some View {
        GroupBox(localized("settings.workspace.agentPresetsGroup")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(localized("settings.workspace.agentPresetsHint"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                if !appSettings.agentPresets.isEmpty {
                    Picker(localized("settings.workspace.agentPreset.default"), selection: Binding(
                        get: { appSettings.preferredAgentPresetID ?? appSettings.agentPresets.first?.id },
                        set: { appSettings.preferredAgentPresetID = $0 }
                    )) {
                        ForEach(appSettings.agentPresets) { preset in
                            Text(preset.name).tag(Optional(preset.id))
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button(localized("settings.workspace.addPreset")) {
                        appSettings.agentPresets.append(
                            AgentPreset(
                                name: localized("defaults.agent.name"),
                                launchPath: "/usr/bin/env",
                                arguments: ["claude"]
                            )
                        )
                        if appSettings.preferredAgentPresetID == nil {
                            appSettings.preferredAgentPresetID = appSettings.agentPresets.last?.id
                        }
                    }
                }

                if appSettings.agentPresets.isEmpty {
                    Text(localized("settings.workspace.agentPresetsEmpty"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(appSettings.agentPresets.indices), id: \.self) { index in
                    agentPresetCard(at: index)
                }
            }
            .padding(.top, 8)
        }
    }

    private var sshPresetsSettingsView: some View {
        GroupBox(localized("settings.workspace.sshPresetsGroup")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(localized("settings.workspace.sshPresetsHint"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    Button(localized("settings.workspace.addSSHPreset")) {
                        appSettings.sshPresets.append(
                            SSHPreset(
                                name: localized("defaults.sshPreset.name"),
                                remoteCommand: ""
                            )
                        )
                    }
                }

                if appSettings.sshPresets.isEmpty {
                    Text(localized("settings.workspace.sshPresetsEmpty"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(appSettings.sshPresets.indices), id: \.self) { index in
                    sshPresetCard(at: index)
                }
            }
            .padding(.top, 8)
        }
    }

    private var selectedWorkspace: WorkspaceModel? {
        guard let selectedWorkspaceID else { return nil }
        return store.workspaces.first(where: { $0.id == selectedWorkspaceID })
    }

    private var workspaceSelector: some View {
        Picker(localized("settings.workspace.selector"), selection: Binding(
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
        originalAppLanguage = store.appSettings.appLanguage
        selectedWorkspaceID = request.workspaceID ?? store.selectedWorkspace?.id
        terminalFontSearchText = ""
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

    @ViewBuilder
    private func agentPresetCard(at index: Int) -> some View {
        let presetBinding = $appSettings.agentPresets[index]
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                TextField(localized("settings.workspace.agentPreset.name"), text: presetBinding.name)
                TextField(localized("settings.workspace.agentPreset.launchPath"), text: presetBinding.launchPath)

                Button {
                    moveAgentPreset(from: index, to: index - 1)
                } label: {
                    Image(systemName: "arrow.up")
                }
                .help(localized("settings.workspace.agentPreset.moveUp"))
                .disabled(index == 0)

                Button {
                    moveAgentPreset(from: index, to: index + 1)
                } label: {
                    Image(systemName: "arrow.down")
                }
                .help(localized("settings.workspace.agentPreset.moveDown"))
                .disabled(index == appSettings.agentPresets.index(before: appSettings.agentPresets.endIndex))

                Button(role: .destructive) {
                    deleteAgentPreset(at: index)
                } label: {
                    Image(systemName: "trash")
                }
            }

            TextField(
                localized("settings.workspace.agentPreset.arguments"),
                text: Binding(
                    get: { presetBinding.wrappedValue.arguments.joined(separator: "\n") },
                    set: { value in
                        presetBinding.wrappedValue.arguments = value
                            .split(whereSeparator: \.isNewline)
                            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                    }
                ),
                axis: .vertical
            )
            .lineLimit(2...5)

            TextField(
                localized("settings.workspace.agentPreset.environment"),
                text: Binding(
                    get: {
                        presetBinding.wrappedValue.environment
                            .sorted { $0.key < $1.key }
                            .map { "\($0.key)=\($0.value)" }
                            .joined(separator: "\n")
                    },
                    set: { value in
                        presetBinding.wrappedValue.environment = value
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

    @ViewBuilder
    private func sshPresetCard(at index: Int) -> some View {
        let presetBinding = $appSettings.sshPresets[index]
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                TextField(localized("settings.workspace.sshPreset.name"), text: presetBinding.name)

                Button {
                    moveSSHPreset(from: index, to: index - 1)
                } label: {
                    Image(systemName: "arrow.up")
                }
                .help(localized("settings.workspace.sshPreset.moveUp"))
                .disabled(index == 0)

                Button {
                    moveSSHPreset(from: index, to: index + 1)
                } label: {
                    Image(systemName: "arrow.down")
                }
                .help(localized("settings.workspace.sshPreset.moveDown"))
                .disabled(index == appSettings.sshPresets.index(before: appSettings.sshPresets.endIndex))

                Button(role: .destructive) {
                    deleteSSHPreset(at: index)
                } label: {
                    Image(systemName: "trash")
                }
            }

            HStack {
                TextField(localized("settings.workspace.remoteTarget.host"), text: Binding(
                    get: { presetBinding.wrappedValue.host ?? "" },
                    set: { presetBinding.wrappedValue.host = $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
                ))
                TextField(localized("settings.workspace.remoteTarget.user"), text: Binding(
                    get: { presetBinding.wrappedValue.user ?? "" },
                    set: { presetBinding.wrappedValue.user = $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
                ))
                TextField(localized("settings.workspace.remoteTarget.port"), text: Binding(
                    get: { presetBinding.wrappedValue.port.map(String.init) ?? "" },
                    set: { presetBinding.wrappedValue.port = Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                ))
                .frame(width: 90)
            }

            TextField(localized("settings.workspace.remoteTarget.identityFile"), text: Binding(
                get: { presetBinding.wrappedValue.identityFilePath ?? "" },
                set: { presetBinding.wrappedValue.identityFilePath = $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            ))

            TextField(localized("settings.workspace.remoteTarget.workspacePath"), text: Binding(
                get: { presetBinding.wrappedValue.remoteWorkingDirectory ?? "" },
                set: { presetBinding.wrappedValue.remoteWorkingDirectory = $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            ))

            TextField(
                localized("settings.workspace.sshPreset.command"),
                text: presetBinding.remoteCommand,
                axis: .vertical
            )
            .lineLimit(2...5)
        }
        .padding(12)
        .background(LineyTheme.subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func moveAgentPreset(from sourceIndex: Int, to destinationIndex: Int) {
        guard appSettings.agentPresets.indices.contains(sourceIndex),
              appSettings.agentPresets.indices.contains(destinationIndex),
              sourceIndex != destinationIndex else {
            return
        }
        let preset = appSettings.agentPresets.remove(at: sourceIndex)
        appSettings.agentPresets.insert(preset, at: destinationIndex)
    }

    private func deleteAgentPreset(at index: Int) {
        guard appSettings.agentPresets.indices.contains(index) else { return }

        let removedPresetID = appSettings.agentPresets[index].id
        appSettings.agentPresets.remove(at: index)

        if appSettings.preferredAgentPresetID == removedPresetID {
            appSettings.preferredAgentPresetID = appSettings.agentPresets.first?.id
        }
    }

    private func moveSSHPreset(from sourceIndex: Int, to destinationIndex: Int) {
        guard appSettings.sshPresets.indices.contains(sourceIndex),
              appSettings.sshPresets.indices.contains(destinationIndex),
              sourceIndex != destinationIndex else {
            return
        }
        let preset = appSettings.sshPresets.remove(at: sourceIndex)
        appSettings.sshPresets.insert(preset, at: destinationIndex)
    }

    private func deleteSSHPreset(at index: Int) {
        guard appSettings.sshPresets.indices.contains(index) else { return }

        let removedPresetID = appSettings.sshPresets[index].id
        appSettings.sshPresets.remove(at: index)

        if appSettings.preferredSSHPresetID == removedPresetID {
            appSettings.preferredSSHPresetID = nil
        }
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

    private var terminalThemeEnabledBinding: Binding<Bool> {
        Binding(
            get: { appSettings.terminalTheme != nil },
            set: { enabled in
                if enabled {
                    appSettings.terminalTheme = appSettings.terminalTheme ?? ""
                } else {
                    appSettings.terminalTheme = nil
                }
            }
        )
    }

    private var terminalThemeBinding: Binding<String> {
        Binding(
            get: { appSettings.terminalTheme ?? "" },
            set: { appSettings.terminalTheme = $0 }
        )
    }

    private var terminalFontFamilyEnabledBinding: Binding<Bool> {
        Binding(
            get: { appSettings.terminalFontFamily != nil },
            set: { enabled in
                if enabled {
                    appSettings.terminalFontFamily = appSettings.terminalFontFamily
                        ?? terminalFontFamilies.first
                        ?? "Menlo"
                } else {
                    appSettings.terminalFontFamily = nil
                }
            }
        )
    }

    private var terminalFontFamilyBinding: Binding<String> {
        Binding(
            get: {
                appSettings.terminalFontFamily
                    ?? terminalFontFamilies.first
                    ?? "Menlo"
            },
            set: { appSettings.terminalFontFamily = $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
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

private struct SettingsNavigationRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
    }
}

private struct TerminalFontOptionRow: View {
    let family: String
    let isSelected: Bool
    let onSelect: () -> Void

    private var previewFont: Font {
        Font(LineyTerminalFontCatalog.previewFont(family: family, size: 12))
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(family)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text("liney % git status --short")
                        .font(previewFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : LineyTheme.subtleFill)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct TerminalFontPreviewCard: View {
    let title: String
    let subtitle: String
    let family: String?
    let usesCustomFamily: Bool
    let size: Double
    let usesCustomSize: Bool
    let defaultFamilyLabel: String
    let customSizeFormat: String
    let defaultSizeFormat: String

    private var previewFont: Font {
        Font(LineyTerminalFontCatalog.previewFont(family: family, size: CGFloat(size)))
    }

    private var activeFamilyLabel: String {
        if usesCustomFamily, let family, !family.isEmpty {
            return family
        }
        return defaultFamilyLabel
    }

    private var activeSizeLabel: String {
        let roundedSize = Int(size.rounded())
        if usesCustomSize {
            return l10nFormat(customSizeFormat, locale: Locale.current, arguments: [roundedSize])
        }
        return l10nFormat(defaultSizeFormat, locale: Locale.current, arguments: [roundedSize])
    }

    var body: some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(activeFamilyLabel)
                        .font(.system(size: 14, weight: .semibold))
                    Text(activeSizeLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Last login: Sat Mar 27 12:03 on ttys004")
                        .foregroundStyle(.secondary)
                    Text("liney % ssh dev@example.com")
                        .foregroundStyle(.green)
                    Text("dev@example.com % git status --short")
                    Text(" M Liney/UI/Sheets/SettingsSheet.swift")
                        .foregroundStyle(.orange)
                    Text("dev@example.com % echo \"0123456789 -> []{}()\"")
                    Text("0123456789 -> []{}()")
                        .foregroundStyle(.secondary)
                }
                .font(previewFont)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.28))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08))
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        }
    }
}

private struct WorkspaceSidebarAppearanceSection: View {
    let store: WorkspaceStore
    let workspace: WorkspaceModel?
    let appSettings: AppSettings
    @Binding var workspaceSettings: WorkspaceSettings

    private func localized(_ key: String) -> String {
        LocalizationManager.shared.string(key)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        l10nFormat(localized(key), locale: Locale.current, arguments: arguments)
    }

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
            Text(localized("settings.sidebarAppearance.title"))
                .font(.system(size: 12, weight: .semibold))

            Toggle(
                localized("settings.sidebarAppearance.customWorkspaceIcon"),
                isOn: Binding(
                    get: { workspaceSettings.workspaceIcon != nil },
                    set: { isEnabled in
                        workspaceSettings.workspaceIcon = isEnabled ? workspaceIconFallback : nil
                    }
                )
            )

            if workspaceSettings.workspaceIcon != nil {
                SidebarIconEditorCard(
                    title: localized("settings.sidebarAppearance.workspaceIcon.title"),
                    subtitle: localized("settings.sidebarAppearance.workspaceIcon.subtitle"),
                    icon: workspaceIconBinding,
                    randomizer: workspaceIconRandomizer
                )
            }

            if let activeWorktree {
                Toggle(
                    localizedFormat("settings.sidebarAppearance.customActiveWorktreeIconFormat", activeWorktree.displayName),
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
                        title: localized("settings.sidebarAppearance.activeWorktreeIcon.title"),
                        subtitle: localized("settings.sidebarAppearance.activeWorktreeIcon.subtitle"),
                        icon: activeWorktreeIconBinding,
                        randomizer: SidebarItemIcon.randomRepository
                    )
                }

                if workspaceSettings.worktreeIconOverrides.count > 0 {
                    Text(localizedFormat("settings.sidebarAppearance.overrideCountFormat", workspaceSettings.worktreeIconOverrides.count))
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

    private func localized(_ key: String) -> String {
        LocalizationManager.shared.string(key)
    }

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

                Button(localized("settings.sidebarIconEditor.random")) {
                    icon = randomizer()
                }
            }

            Picker(localized("settings.sidebarIconEditor.symbol"), selection: $icon.symbolName) {
                ForEach(SidebarIconCatalog.symbols, id: \.systemName) { symbol in
                    Label(symbol.title, systemImage: symbol.systemName).tag(symbol.systemName)
                }
            }

            Picker(localized("settings.sidebarIconEditor.style"), selection: $icon.fillStyle) {
                ForEach(SidebarIconFillStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 8) {
                Text(localized("settings.sidebarIconEditor.palette"))
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

    private func localized(_ key: String) -> String {
        LocalizationManager.shared.string(key)
    }

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
        action.defaultShortcut == nil ? localized("common.clear") : localized("common.disable")
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
                emptyTitle: localized("common.notSet"),
                displayString: { action.displayedShortcutString(for: $0) },
                transformRecordedShortcut: action.normalizedRecordedShortcut
            )
            .frame(width: 132)

            Button(disableButtonTitle, action: onDisable)
                .disabled(!canDisable)

            Button(localized("common.reset"), action: onReset)
                .disabled(!canReset)
        }
        .padding(.vertical, 2)
    }
}

struct ShortcutRecorderField: NSViewRepresentable {
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
        nsView.onShortcutRecorded = { newShortcut in
            shortcut = newShortcut
        }
        nsView.updateTitle()
    }
}

final class ShortcutRecorderNSButton: NSButton {
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
            title = LocalizationManager.shared.string("shortcuts.recorder.pressShortcut")
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

    private func localized(_ key: String) -> String {
        LocalizationManager.shared.string(key)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(localized("settings.sidebarIconCustomization.title"))
                .font(.system(size: 20, weight: .semibold))

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            SidebarIconEditorCard(
                title: localized("settings.sidebarIconCustomization.icon.title"),
                subtitle: localized("settings.sidebarIconCustomization.icon.subtitle"),
                icon: $icon,
                randomizer: randomizer
            )

            HStack {
                Spacer()
                if resetSupported {
                    Button {
                        store.resetSidebarIcon(for: request.target)
                        dismiss()
                    } label: {
                        Label(localized("settings.sidebarIconCustomization.reset"), systemImage: "arrow.counterclockwise")
                    }
                }
                Button {
                    dismiss()
                } label: {
                    Label(localized("settings.button.cancel"), systemImage: "xmark")
                }
                Button {
                    store.updateSidebarIcon(icon, for: request.target)
                    dismiss()
                } label: {
                    Label(localized("settings.button.save"), systemImage: "checkmark")
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
        case .workspaceGroup:
            return SidebarItemIcon.random
        case .appDefaultLocalTerminal:
            return SidebarItemIcon.random
        }
    }
}
