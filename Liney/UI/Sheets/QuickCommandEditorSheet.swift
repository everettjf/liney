//
//  QuickCommandEditorSheet.swift
//  Liney
//
//  Author: everettjf
//

import SwiftUI

struct QuickCommandEditorSheet: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss

    @State private var draftCommands: [QuickCommandPreset] = []
    @State private var selectedCommandID: String?
    @State private var searchQuery = ""
    @State private var isLoading = true
    @State private var showDiscardChangesAlert = false

    private func localized(_ key: String) -> String {
        LocalizationManager.shared.string(key)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        l10nFormat(localized(key), locale: Locale.current, arguments: arguments)
    }

    var body: some View {
        ZStack {
            LineyTheme.appBackground

            VStack(spacing: 0) {
                topBar

                HStack(spacing: 0) {
                    sidebar

                    Divider()

                    detailPane
                }

                footer
            }
        }
        .frame(width: 980, height: 660)
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
            draftCommands = store.quickCommandPresets
            syncSelection()
            isLoading = false
        }
        .onChange(of: draftCommands.map(\.id)) { _, _ in
            syncSelection()
        }
        .onChange(of: searchQuery) { _, _ in
            syncSelection(preferVisible: true)
        }
        .alert(localized("sheet.quickCommands.unsavedChangesTitle"), isPresented: $showDiscardChangesAlert) {
            Button(localized("sheet.quickCommands.saveChanges")) {
                saveAndDismiss()
            }
            Button(localized("sheet.quickCommands.discardChanges"), role: .destructive) {
                dismiss()
            }
            Button(localized("sheet.quickCommands.continueEditing"), role: .cancel) {}
        } message: {
            Text(localized("sheet.quickCommands.unsavedChangesMessage"))
        }
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(localized("sheet.quickCommands.title"))
                    .font(.system(size: 19, weight: .semibold))

                Text(localized("sheet.quickCommands.shortcutHint"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(LineyTheme.mutedText)
            }

            Spacer()

            Text(localizedFormat("sheet.quickCommands.countFormat", draftCommands.count))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(LineyTheme.secondaryText)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(LineyTheme.subtleFill, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(LineyTheme.border, lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(LineyTheme.panelBackground.opacity(0.98))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LineyTheme.border)
                .frame(height: 1)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button(localized("sheet.quickCommands.add")) {
                    addCommand()
                }
                .buttonStyle(.borderedProminent)

                Button(localized("sheet.quickCommands.resetDefaults")) {
                    resetCommands()
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(LineyTheme.mutedText)

                TextField(localized("sheet.quickCommands.searchPlaceholder"), text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))

                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(LineyTheme.mutedText)
                    }
                    .buttonStyle(.plain)
                }
            }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(LineyTheme.subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(LineyTheme.border, lineWidth: 1)
            )

            if isLoading {
                QuickCommandLoadingState(localized: localized)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else if draftCommands.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(localized("sheet.quickCommands.empty"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(LineyTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(LineyTheme.subtleFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(LineyTheme.border, lineWidth: 1)
                )
            } else if filteredSections.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(localized("sheet.quickCommands.noResults"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(LineyTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(LineyTheme.subtleFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(LineyTheme.border, lineWidth: 1)
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(filteredSections) { section in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(section.category.title)
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(LineyTheme.secondaryText)
                                        .textCase(.uppercase)

                                    Spacer()

                                    Text("\(section.commands.count)")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(LineyTheme.mutedText)
                                }

                                VStack(spacing: 4) {
                                    ForEach(section.commands) { command in
                                        QuickCommandListItem(
                                            command: command,
                                            isSelected: command.id == selectedCommandID,
                                            onSelect: { selectedCommandID = command.id }
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(16)
        .frame(width: 272)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(LineyTheme.appBackground.opacity(0.16))
    }

    private var detailPane: some View {
        Group {
            if isLoading {
                QuickCommandDetailLoadingState(localized: localized)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(14)
            } else if let commandBinding = selectedCommandBinding {
                QuickCommandDetailPanel(
                    command: commandBinding,
                    canMoveUp: canMoveSelectedUp,
                    canMoveDown: canMoveSelectedDown,
                    onMoveUp: moveSelectedUp,
                    onMoveDown: moveSelectedDown,
                    onDelete: deleteSelectedCommand,
                    localized: localized
                )
                .padding(14)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text(localized("sheet.quickCommands.empty"))
                        .font(.system(size: 18, weight: .semibold))

                    Text(localized("sheet.quickCommands.searchPlaceholder"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(LineyTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LineyTheme.panelBackground.opacity(0.72))
    }

    private var footer: some View {
        HStack {
            Spacer()

            Button(localized("common.cancel")) {
                requestDismiss()
            }

            Button(localized("common.save")) {
                saveAndDismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(LineyTheme.panelBackground.opacity(0.98))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(LineyTheme.border)
                .frame(height: 1)
        }
    }

    private var selectedCommandBinding: Binding<QuickCommandPreset>? {
        guard let selectedCommandID,
              draftCommands.contains(where: { $0.id == selectedCommandID }) else {
            return nil
        }

        return Binding(
            get: {
                draftCommands.first(where: { $0.id == selectedCommandID })!
            },
            set: { updated in
                guard let index = draftCommands.firstIndex(where: { $0.id == selectedCommandID }) else { return }
                draftCommands[index] = updated
            }
        )
    }

    private var selectedIndex: Int? {
        guard let selectedCommandID else { return nil }
        return draftCommands.firstIndex(where: { $0.id == selectedCommandID })
    }

    private var filteredSections: [QuickCommandCategorySection] {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredCommands: [QuickCommandPreset]

        if trimmedQuery.isEmpty {
            filteredCommands = draftCommands
        } else {
            let query = trimmedQuery.lowercased()
            filteredCommands = draftCommands.filter { command in
                command.normalizedTitle.lowercased().contains(query) ||
                command.normalizedCommand.lowercased().contains(query) ||
                command.category.title.lowercased().contains(query)
            }
        }

        return QuickCommandCategory.allCases.compactMap { category in
            let commands = filteredCommands.filter { $0.category == category }
            guard !commands.isEmpty else { return nil }
            return QuickCommandCategorySection(category: category, commands: commands)
        }
    }

    private var visibleCommandIDs: Set<String> {
        Set(filteredSections.flatMap { $0.commands.map(\.id) })
    }

    private var canMoveSelectedUp: Bool {
        guard let selectedIndex else { return false }
        return selectedIndex > 0
    }

    private var canMoveSelectedDown: Bool {
        guard let selectedIndex else { return false }
        return selectedIndex < draftCommands.count - 1
    }

    private func syncSelection(preferVisible: Bool = false) {
        if let selectedCommandID,
           draftCommands.contains(where: { $0.id == selectedCommandID }) {
            if preferVisible, !visibleCommandIDs.contains(selectedCommandID) {
                self.selectedCommandID = filteredSections.first?.commands.first?.id
            }
            return
        }

        selectedCommandID = filteredSections.first?.commands.first?.id ?? draftCommands.first?.id
    }

    private func addCommand() {
        let newCommand = QuickCommandPreset(
            title: localized("sheet.quickCommands.defaultName"),
            command: "",
            category: .codex
        )
        draftCommands.append(newCommand)
        selectedCommandID = newCommand.id
    }

    private func resetCommands() {
        draftCommands = QuickCommandCatalog.defaultCommands
        selectedCommandID = draftCommands.first?.id
    }

    private func moveSelectedUp() {
        guard let selectedIndex, selectedIndex > 0 else { return }
        moveCommand(from: selectedIndex, to: selectedIndex - 1)
    }

    private func moveSelectedDown() {
        guard let selectedIndex, selectedIndex < draftCommands.count - 1 else { return }
        moveCommand(from: selectedIndex, to: selectedIndex + 1)
    }

    private func deleteSelectedCommand() {
        guard let selectedIndex else { return }

        draftCommands.remove(at: selectedIndex)

        if draftCommands.indices.contains(selectedIndex) {
            selectedCommandID = draftCommands[selectedIndex].id
        } else {
            selectedCommandID = draftCommands.last?.id
        }
    }

    private func moveCommand(from source: Int, to destination: Int) {
        guard draftCommands.indices.contains(source),
              draftCommands.indices.contains(destination),
              source != destination else {
            return
        }

        let item = draftCommands.remove(at: source)
        draftCommands.insert(item, at: destination)
        selectedCommandID = item.id
    }

    private var hasUnsavedChanges: Bool {
        !isLoading && draftCommands != store.quickCommandPresets
    }

    private func requestDismiss() {
        if hasUnsavedChanges {
            showDiscardChangesAlert = true
            return
        }

        dismiss()
    }

    private func saveAndDismiss() {
        store.updateQuickCommandPresets(draftCommands)
        dismiss()
    }
}

private struct QuickCommandCategorySection: Identifiable {
    let category: QuickCommandCategory
    let commands: [QuickCommandPreset]

    var id: String { category.id }
}

private struct QuickCommandLoadingState: View {
    let localized: (String) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localized("common.loading"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(LineyTheme.secondaryText)

            VStack(spacing: 4) {
                QuickCommandLoadingRow()
                QuickCommandLoadingRow()
                QuickCommandLoadingRow()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(LineyTheme.subtleFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(LineyTheme.border, lineWidth: 1)
        )
    }
}

private struct QuickCommandDetailLoadingState: View {
    let localized: (String) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(LineyTheme.subtleRaisedFill)
                    .frame(width: 16, height: 16)

                VStack(alignment: .leading, spacing: 4) {
                    QuickCommandSkeletonBar(width: 220, height: 18)
                    QuickCommandSkeletonBar(width: 56, height: 10)
                }

                Spacer()

                HStack(spacing: 6) {
                    QuickCommandSkeletonButton()
                    QuickCommandSkeletonButton()
                    QuickCommandSkeletonButton()
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                loadingField(width: 40)
                loadingFieldPair()
                loadingCommandEditor()
                loadingToggleCard()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LineyTheme.panelRaised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(LineyTheme.border, lineWidth: 1)
        )
    }

    private func loadingField(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            QuickCommandSkeletonBar(width: width, height: 10)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LineyTheme.subtleFill)
                .frame(height: 34)
        }
    }

    private func loadingFieldPair() -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                QuickCommandSkeletonBar(width: 58, height: 10)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LineyTheme.subtleFill)
                    .frame(height: 34)
            }

            VStack(alignment: .leading, spacing: 8) {
                QuickCommandSkeletonBar(width: 78, height: 10)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LineyTheme.subtleFill)
                    .frame(height: 34)
            }
        }
    }

    private func loadingCommandEditor() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            QuickCommandSkeletonBar(width: 62, height: 10)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LineyTheme.subtleFill)
                .frame(height: 178)
        }
    }

    private func loadingToggleCard() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                QuickCommandSkeletonBar(width: 280, height: 12)
                Spacer()
                Capsule()
                    .fill(LineyTheme.subtleRaisedFill)
                    .frame(width: 58, height: 30)
            }

            QuickCommandSkeletonBar(width: 240, height: 12)
        }
    }
}

private struct QuickCommandLoadingRow: View {
    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(LineyTheme.subtleRaisedFill)
                .frame(width: 14, height: 14)

            VStack(alignment: .leading, spacing: 4) {
                QuickCommandSkeletonBar(width: 120, height: 11)
                QuickCommandSkeletonBar(width: 90, height: 9)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(LineyTheme.appBackground.opacity(0.28), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct QuickCommandSkeletonBar: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(LineyTheme.subtleRaisedFill)
            .frame(width: width, height: height)
    }
}

private struct QuickCommandSkeletonButton: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(LineyTheme.subtleFill)
            .frame(width: 32, height: 30)
    }
}

private struct QuickCommandListItem: View {
    let command: QuickCommandPreset
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: command.category.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 14, height: 14)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(command.normalizedTitle)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(LineyTheme.tertiaryText)
                            .lineLimit(1)

                        if command.submitsReturn {
                            QuickCommandMetaTag(title: "Return", tint: LineyTheme.success)
                        }

                        Spacer(minLength: 0)

                        if let shortcut = command.shortcut {
                            Text(shortcut.displayString)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(LineyTheme.mutedText)
                                .lineLimit(1)
                        }
                    }

                    Text(command.normalizedCommand.nilIfEmpty ?? " ")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(LineyTheme.mutedText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundShape.fill(backgroundColor))
            .overlay(
                backgroundShape
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var backgroundShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    private var backgroundColor: Color {
        isSelected ? tint.opacity(0.16) : LineyTheme.subtleFill
    }

    private var borderColor: Color {
        isSelected ? tint.opacity(0.55) : LineyTheme.border
    }

    private var tint: Color {
        switch command.category {
        case .codex:
            return LineyTheme.accent
        case .claude:
            return LineyTheme.warning
        case .cloud:
            return LineyTheme.localAccent
        case .linux:
            return LineyTheme.secondaryText
        }
    }
}

private struct QuickCommandDetailPanel: View {
    @Binding var command: QuickCommandPreset
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void
    let localized: (String) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                ToolbarFeatureIcon(
                    systemName: command.category.symbolName,
                    tint: tint
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(command.normalizedTitle)
                        .font(.system(size: 18, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(command.category.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tint)
                }

                Spacer()

                HStack(spacing: 6) {
                    Button(action: onMoveUp) {
                        Image(systemName: "arrow.up")
                    }
                    .disabled(!canMoveUp)

                    Button(action: onMoveDown) {
                        Image(systemName: "arrow.down")
                    }
                    .disabled(!canMoveDown)

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 12) {
                detailField(title: localized("sheet.quickCommands.commandTitle")) {
                    TextField(localized("sheet.quickCommands.commandTitle"), text: $command.title)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, weight: .medium))
                }

                HStack(alignment: .top, spacing: 16) {
                    detailField(title: localized("sheet.quickCommands.category")) {
                        Picker(localized("sheet.quickCommands.category"), selection: $command.category) {
                            ForEach(QuickCommandCategory.allCases) { category in
                                Text(category.title).tag(category)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    detailField(title: localized("sheet.quickCommands.shortcutPlaceholder")) {
                        ShortcutRecorderField(
                            shortcut: $command.shortcut,
                            fallbackShortcut: StoredShortcut(key: "k", command: true, shift: false, option: false, control: false),
                            emptyTitle: localized("sheet.quickCommands.shortcutPlaceholder"),
                            displayString: { $0.displayString },
                            transformRecordedShortcut: { $0 }
                        )
                    }
                }

                detailField(title: localized("sheet.quickCommands.commandBody")) {
                    TextEditor(text: $command.command)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 160)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.035))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(LineyTheme.border, lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: 10) {
                    Toggle(localized("sheet.quickCommands.autoReturn"), isOn: $command.submitsReturn)
                        .toggleStyle(.switch)
                        .font(.system(size: 12, weight: .semibold))

                    Text(
                        command.submitsReturn
                        ? localized("sheet.quickCommands.autoReturnEnabledDetail")
                        : localized("sheet.quickCommands.autoReturnDisabledDetail")
                    )
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(LineyTheme.mutedText)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LineyTheme.subtleFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(LineyTheme.border, lineWidth: 1)
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LineyTheme.panelRaised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(LineyTheme.border, lineWidth: 1)
        )
    }

    private func detailField<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(LineyTheme.secondaryText)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tint: Color {
        switch command.category {
        case .codex:
            return LineyTheme.accent
        case .claude:
            return LineyTheme.warning
        case .cloud:
            return LineyTheme.localAccent
        case .linux:
            return LineyTheme.secondaryText
        }
    }
}

private struct QuickCommandMetaTag: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(tint.opacity(0.12), in: Capsule())
    }
}
