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
    @State private var draftCategories: [QuickCommandCategory] = []
    @State private var selectedCommandID: String?
    @State private var searchQuery = ""
    @State private var isLoading = true
    @State private var showDiscardChangesAlert = false
    @State private var showPredefinedLibrary = false
    @State private var showCategoryManager = false

    private func localized(_ key: String) -> String {
        LocalizationManager.shared.string(key)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        l10nFormat(localized(key), locale: Locale.current, arguments: arguments)
    }

    private var categoryMap: [String: QuickCommandCategory] {
        QuickCommandCatalog.categoryMap(draftCategories)
    }

    private var availableCategories: [QuickCommandCategory] {
        QuickCommandCatalog.normalizedCategories(draftCategories)
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
        .frame(width: 1080, height: 700)
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
            draftCategories = store.quickCommandCategories
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
        .sheet(isPresented: $showPredefinedLibrary) {
            QuickCommandLibrarySheet(
                existingCommandIDs: Set(draftCommands.map(\.id)),
                onImport: { templates in
                    importPredefinedCommands(templates)
                },
                localized: localized
            )
        }
        .sheet(isPresented: $showCategoryManager) {
            QuickCommandCategoryManagerSheet(
                categories: draftCategories,
                commands: draftCommands,
                onSave: { categories, commands in
                    draftCategories = categories
                    draftCommands = commands
                    syncSelection(preferVisible: true)
                },
                localized: localized
            )
        }
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            Text(localized("sheet.quickCommands.title"))
                .font(.system(size: 19, weight: .semibold))

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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                QuickCommandCompactButton(
                    systemName: "plus",
                    title: localized("sheet.quickCommands.addCompact"),
                    tint: LineyTheme.accent,
                    action: addCommand
                )
                QuickCommandCompactButton(
                    systemName: "square.and.arrow.down",
                    title: localized("sheet.quickCommands.addPredefined"),
                    tint: LineyTheme.localAccent,
                    action: { showPredefinedLibrary = true }
                )

                Spacer()

                QuickCommandCompactMenu(
                    systemName: "ellipsis",
                    title: localized("sheet.quickCommands.more"),
                    tint: LineyTheme.warning,
                    localized: localized,
                    showCategoryManager: {
                        showCategoryManager = true
                    },
                    resetCommands: resetCommands
                )
            }

            if isLoading {
                QuickCommandLoadingState(localized: localized)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else if draftCommands.isEmpty {
                infoCard(localized("sheet.quickCommands.empty"))
            } else if filteredSections.isEmpty {
                infoCard(localized("sheet.quickCommands.noResults"))
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
                                            category: section.category,
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
        }
        .padding(16)
        .frame(width: 340)
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
                    category: resolvedCategory(for: commandBinding.wrappedValue),
                    categories: availableCategories,
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

            Button {
                requestDismiss()
            } label: {
                Label(localized("common.cancel"), systemImage: "xmark")
            }

            Button {
                saveAndDismiss()
            } label: {
                Label(localized("common.save"), systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
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
                let resolvedCommands = QuickCommandCatalog.replacingCommand(updated, in: draftCommands)
                draftCommands = resolvedCommands
                self.selectedCommandID = resolvedCommands[index].id
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
                let category = resolvedCategory(for: command)
                return command.normalizedTitle.lowercased().contains(query) ||
                    command.normalizedCommand.lowercased().contains(query) ||
                    category.title.lowercased().contains(query)
            }
        }

        let visibleCategories = QuickCommandCatalog.visibleCategories(
            commands: filteredCommands,
            categories: draftCategories
        )

        return visibleCategories.compactMap { category in
            let commands = filteredCommands.filter { $0.categoryID == category.id }
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

    private var hasUnsavedChanges: Bool {
        !isLoading &&
        (draftCommands != store.quickCommandPresets || draftCategories != store.quickCommandCategories)
    }

    private func resolvedCategory(for command: QuickCommandPreset) -> QuickCommandCategory {
        categoryMap[command.categoryID] ?? .fallbackCategory
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
            categoryID: QuickCommandCategory.defaultCategory.id
        )
        draftCommands.append(newCommand)
        selectedCommandID = newCommand.id
    }

    private func importPredefinedCommands(_ templates: [QuickCommandPreset]) {
        let existingIDs = Set(draftCommands.map(\.id))
        let imports = templates.filter { !existingIDs.contains($0.id) }
        guard !imports.isEmpty else { return }
        draftCommands.append(contentsOf: imports)
        selectedCommandID = imports.first?.id
    }

    private func resetCommands() {
        draftCategories = QuickCommandCatalog.defaultCategories
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

    private func requestDismiss() {
        if hasUnsavedChanges {
            showDiscardChangesAlert = true
            return
        }

        dismiss()
    }

    private func saveAndDismiss() {
        store.updateQuickCommands(commands: draftCommands, categories: draftCategories)
        dismiss()
    }

    @ViewBuilder
    private func infoCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
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
    }
}

private struct QuickCommandCategorySection: Identifiable {
    let category: QuickCommandCategory
    let commands: [QuickCommandPreset]

    var id: String { category.id }
}

private struct QuickCommandCompactButton: View {
    let systemName: String
    let title: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(LineyTheme.subtleFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(LineyTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

private struct QuickCommandCompactMenu: View {
    let systemName: String
    let title: String
    let tint: Color
    let localized: (String) -> String
    let showCategoryManager: () -> Void
    let resetCommands: () -> Void

    var body: some View {
        Menu {
            Button {
                showCategoryManager()
            } label: {
                Label(localized("sheet.quickCommands.manageCategories"), systemImage: "tag")
            }

            Divider()

            Button(role: .destructive) {
                resetCommands()
            } label: {
                Label(localized("sheet.quickCommands.resetDefaults"), systemImage: "arrow.counterclockwise")
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(LineyTheme.subtleFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(LineyTheme.border, lineWidth: 1)
                )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help(title)
    }
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
    let category: QuickCommandCategory
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: category.symbolName)
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
        quickCommandCategoryTint(category.id)
    }
}

private struct QuickCommandDetailPanel: View {
    @Binding var command: QuickCommandPreset
    let category: QuickCommandCategory
    let categories: [QuickCommandCategory]
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
                    systemName: category.symbolName,
                    tint: tint
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(command.normalizedTitle)
                        .font(.system(size: 18, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(category.title)
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
                        Picker(localized("sheet.quickCommands.category"), selection: $command.categoryID) {
                            ForEach(categories) { category in
                                Text(category.title).tag(category.id)
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
        quickCommandCategoryTint(category.id)
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

private struct QuickCommandLibrarySheet: View {
    @Environment(\.dismiss) private var dismiss

    let existingCommandIDs: Set<String>
    let onImport: ([QuickCommandPreset]) -> Void
    let localized: (String) -> String

    @State private var searchQuery = ""
    @State private var selectedCategoryID = "all"
    @State private var selectedCommandIDs = Set<String>()
    @State private var complexScope: ComplexLibraryScope = .recommended

    private enum ComplexLibraryScope: String, CaseIterable, Identifiable {
        case recommended
        case all

        var id: String { rawValue }
    }

    private var categories: [QuickCommandCategory] {
        let visible = QuickCommandCatalog.visibleCategories(
            commands: QuickCommandCatalog.predefinedCommands,
            categories: QuickCommandCatalog.defaultCategories
        )

        return visible.sorted { lhs, rhs in
            if lhs.id == QuickCommandCategory.complex.id { return true }
            if rhs.id == QuickCommandCategory.complex.id { return false }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private var filteredCommands: [QuickCommandPreset] {
        let commands = QuickCommandCatalog.predefinedCommands.filter { command in
            let category = QuickCommandCatalog.resolvedCategory(id: command.categoryID, in: QuickCommandCatalog.defaultCategories)
            let matchesCategory = selectedCategoryID == "all" || command.categoryID == selectedCategoryID
            let matchesQuery: Bool
            let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if query.isEmpty {
                matchesQuery = true
            } else {
                matchesQuery = command.normalizedTitle.lowercased().contains(query) ||
                    command.normalizedCommand.lowercased().contains(query) ||
                    category.title.lowercased().contains(query)
            }
            let matchesComplexScope: Bool
            if selectedCategoryID == QuickCommandCategory.complex.id && query.isEmpty && complexScope == .recommended {
                matchesComplexScope = QuickCommandCatalog.isRecommendedComplexCommand(command)
            } else {
                matchesComplexScope = true
            }

            return matchesCategory && matchesQuery && matchesComplexScope
        }

        if selectedCategoryID == QuickCommandCategory.complex.id &&
            searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            complexScope == .recommended {
            return QuickCommandCatalog.sortedRecommendedComplexCommands(commands)
        }

        return commands
    }

    private var selectableFilteredCommands: [QuickCommandPreset] {
        filteredCommands.filter { !existingCommandIDs.contains($0.id) }
    }

    private var showsComplexRecommendedScope: Bool {
        selectedCategoryID == QuickCommandCategory.complex.id &&
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            LineyTheme.appBackground

            VStack(spacing: 0) {
                HStack {
                    Text(localized("sheet.quickCommands.libraryTitle"))
                        .font(.system(size: 17, weight: .semibold))

                    Spacer()

                    HStack(spacing: 8) {
                        Button(localized("sheet.quickCommands.libraryClearSelection")) {
                            selectedCommandIDs.removeAll()
                        }
                        .buttonStyle(.bordered)
                        .disabled(selectedCommandIDs.isEmpty)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 10)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(LineyTheme.border)
                        .frame(height: 1)
                }

                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(LineyTheme.mutedText)

                            TextField(localized("sheet.quickCommands.searchPlaceholder"), text: $searchQuery)
                                .textFieldStyle(.plain)
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(LineyTheme.subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(LineyTheme.border, lineWidth: 1)
                        )

                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                Button {
                                    selectedCategoryID = "all"
                                } label: {
                                    QuickCommandLibraryCategoryRow(
                                        title: localized("sheet.quickCommands.libraryAllCategories"),
                                        isSelected: selectedCategoryID == "all"
                                    )
                                }
                                .buttonStyle(.plain)

                                ForEach(categories) { category in
                                    Button {
                                        selectedCategoryID = category.id
                                    } label: {
                                        QuickCommandLibraryCategoryRow(
                                            title: category.title,
                                            systemName: category.symbolName,
                                            isSelected: selectedCategoryID == category.id
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.top, 2)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(width: 220)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .background(LineyTheme.appBackground.opacity(0.16))

                    Divider()

                    Group {
                        if filteredCommands.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(localized("sheet.quickCommands.noResults"))
                                    .font(.system(size: 15, weight: .semibold))

                                Text(localized("sheet.quickCommands.searchPlaceholder"))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(LineyTheme.secondaryText)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .padding(24)
                        } else {
                            VStack(spacing: 0) {
                                if showsComplexRecommendedScope {
                                    HStack {
                                        Picker("", selection: $complexScope) {
                                            Text(localized("sheet.quickCommands.libraryComplexRecommended")).tag(ComplexLibraryScope.recommended)
                                            Text(localized("sheet.quickCommands.libraryComplexAll")).tag(ComplexLibraryScope.all)
                                        }
                                        .pickerStyle(.segmented)
                                        .frame(width: 220)

                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.top, 8)
                                    .padding(.bottom, 6)
                                }

                                ScrollView {
                                    LazyVStack(spacing: 8) {
                                        ForEach(filteredCommands) { command in
                                            let category = QuickCommandCatalog.resolvedCategory(id: command.categoryID, in: QuickCommandCatalog.defaultCategories)
                                            QuickCommandLibraryItem(
                                                command: command,
                                                category: category,
                                                isSelected: selectedCommandIDs.contains(command.id),
                                                isAlreadyImported: existingCommandIDs.contains(command.id),
                                                toggle: { toggleSelection(for: command) }
                                            )
                                        }
                                    }
                                    .padding(16)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                HStack {
                    Text(
                        l10nFormat(
                            localized("sheet.quickCommands.librarySelectionFormat"),
                            locale: Locale.current,
                            arguments: [selectedCommandIDs.count]
                        )
                    )
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LineyTheme.secondaryText)

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Label(localized("common.cancel"), systemImage: "xmark")
                    }

                    Button {
                        let selectedTemplates = QuickCommandCatalog.predefinedCommands.filter { selectedCommandIDs.contains($0.id) }
                        onImport(selectedTemplates)
                        dismiss()
                    } label: {
                        Label(localized("sheet.quickCommands.libraryImport"), systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedCommandIDs.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(LineyTheme.border)
                        .frame(height: 1)
                }
            }
            .frame(width: 900, height: 500)
            .background(
                LineyTheme.panelBackground,
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(LineyTheme.border, lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 924, height: 520)
    }

    private func toggleSelection(for command: QuickCommandPreset) {
        guard !existingCommandIDs.contains(command.id) else { return }
        if selectedCommandIDs.contains(command.id) {
            selectedCommandIDs.remove(command.id)
        } else {
            selectedCommandIDs.insert(command.id)
        }
    }
}

private struct QuickCommandLibraryCategoryRow: View {
    let title: String
    var systemName: String = "square.grid.2x2"
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 16, height: 16)

            Text(title)
                .font(.system(size: 12, weight: .semibold))

            Spacer()
        }
        .foregroundStyle(isSelected ? LineyTheme.accent : LineyTheme.secondaryText)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? LineyTheme.accent.opacity(0.12) : LineyTheme.subtleFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? LineyTheme.accent.opacity(0.35) : LineyTheme.border, lineWidth: 1)
        )
    }
}

private struct QuickCommandLibraryItem: View {
    let command: QuickCommandPreset
    let category: QuickCommandCategory
    let isSelected: Bool
    let isAlreadyImported: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: category.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(quickCommandCategoryTint(category.id))
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(command.normalizedTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(LineyTheme.tertiaryText)

                        Spacer()

                        if isAlreadyImported {
                            QuickCommandMetaTag(title: "Added", tint: LineyTheme.secondaryText)
                        } else if isSelected {
                            QuickCommandMetaTag(title: "Selected", tint: LineyTheme.accent)
                        }
                    }

                    Text(category.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(quickCommandCategoryTint(category.id))

                    Text(command.command)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(LineyTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isAlreadyImported)
    }

    private var backgroundColor: Color {
        if isAlreadyImported {
            return LineyTheme.subtleFill
        }
        return isSelected ? LineyTheme.accent.opacity(0.12) : LineyTheme.panelRaised
    }

    private var borderColor: Color {
        if isAlreadyImported {
            return LineyTheme.border
        }
        return isSelected ? LineyTheme.accent.opacity(0.35) : LineyTheme.border
    }
}

private struct QuickCommandCategoryManagerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var categories: [QuickCommandCategory]
    @State private var commands: [QuickCommandPreset]

    let onSave: ([QuickCommandCategory], [QuickCommandPreset]) -> Void
    let localized: (String) -> String

    init(
        categories: [QuickCommandCategory],
        commands: [QuickCommandPreset],
        onSave: @escaping ([QuickCommandCategory], [QuickCommandPreset]) -> Void,
        localized: @escaping (String) -> String
    ) {
        _categories = State(initialValue: categories)
        _commands = State(initialValue: commands)
        self.onSave = onSave
        self.localized = localized
    }

    private var customCategories: [QuickCommandCategory] {
        QuickCommandCatalog.normalizedCategories(categories).filter { !$0.isBuiltIn }
    }

    private static let symbolOptions = [
        "tag",
        "terminal",
        "sparkles",
        "hammer",
        "wrench.and.screwdriver",
        "folder",
        "doc.text",
        "network",
        "server.rack",
        "shippingbox"
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localized("sheet.quickCommands.categoriesTitle"))
                        .font(.system(size: 18, weight: .semibold))

                    Text(localized("sheet.quickCommands.categoriesSubtitle"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LineyTheme.secondaryText)
                }

                Spacer()

                Button {
                    categories.append(
                        QuickCommandCategory(
                            id: "custom-\(UUID().uuidString.lowercased())",
                            title: localized("sheet.quickCommands.newCategory"),
                            symbolName: "tag"
                        )
                    )
                } label: {
                    Label(localized("sheet.quickCommands.addCategory"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(18)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(LineyTheme.border)
                    .frame(height: 1)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(localized("sheet.quickCommands.builtInCategories"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(LineyTheme.secondaryText)

                        ForEach(QuickCommandCategory.builtInCategories) { category in
                            HStack(spacing: 12) {
                                ToolbarFeatureIcon(
                                    systemName: category.symbolName,
                                    tint: quickCommandCategoryTint(category.id)
                                )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(category.title)
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(localized("sheet.quickCommands.builtInCategoryHint"))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(LineyTheme.secondaryText)
                                }

                                Spacer()
                            }
                            .padding(12)
                            .background(LineyTheme.subtleFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(LineyTheme.border, lineWidth: 1)
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(localized("sheet.quickCommands.customCategories"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(LineyTheme.secondaryText)

                        if customCategories.isEmpty {
                            Text(localized("sheet.quickCommands.noCustomCategories"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(LineyTheme.secondaryText)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(LineyTheme.subtleFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        } else {
                            ForEach(customCategories) { category in
                                customCategoryRow(category)
                            }
                        }
                    }
                }
                .padding(18)
            }

            HStack {
                Spacer()

                Button {
                    dismiss()
                } label: {
                    Label(localized("common.cancel"), systemImage: "xmark")
                }

                Button {
                    onSave(QuickCommandCatalog.normalizedCategories(categories), commands)
                    dismiss()
                } label: {
                    Label(localized("common.save"), systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(LineyTheme.border)
                    .frame(height: 1)
            }
        }
        .frame(width: 720, height: 620)
        .background(LineyTheme.panelBackground)
    }

    @ViewBuilder
    private func customCategoryRow(_ category: QuickCommandCategory) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ToolbarFeatureIcon(
                        systemName: category.symbolName,
                        tint: quickCommandCategoryTint(category.id)
                    )

                    TextField(
                        localized("sheet.quickCommands.category"),
                        text: Binding(
                            get: { category.title },
                            set: { updateCategoryTitle(id: category.id, title: $0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    Text(
                        l10nFormat(
                            localized("sheet.quickCommands.categoryUsageFormat"),
                            locale: Locale.current,
                            arguments: [usageCount(for: category.id)]
                        )
                    )
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(LineyTheme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(LineyTheme.panelBackground, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(LineyTheme.border, lineWidth: 1)
                    )
                }

                Picker(localized("sheet.quickCommands.categoryIcon"), selection: Binding(
                    get: { category.symbolName },
                    set: { updateCategorySymbol(id: category.id, symbolName: $0) }
                )) {
                    ForEach(Self.symbolOptions, id: \.self) { symbol in
                        Label(symbolLabel(for: symbol), systemImage: symbol).tag(symbol)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(role: .destructive) {
                deleteCategory(category.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(LineyTheme.subtleFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(LineyTheme.border, lineWidth: 1)
        )
    }

    private func updateCategoryTitle(id: String, title: String) {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[index].title = title
    }

    private func updateCategorySymbol(id: String, symbolName: String) {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[index].symbolName = symbolName
    }

    private func deleteCategory(_ id: String) {
        categories.removeAll { $0.id == id }
        commands = commands.map { command in
            guard command.categoryID == id else { return command }
            var updated = command
            updated.categoryID = QuickCommandCategory.fallbackCategory.id
            return updated
        }
    }

    private func usageCount(for id: String) -> Int {
        commands.filter { $0.categoryID == id }.count
    }

    private func symbolLabel(for symbol: String) -> String {
        switch symbol {
        case "tag":
            return localized("sheet.quickCommands.symbolTag")
        case "terminal":
            return localized("sheet.quickCommands.symbolTerminal")
        case "sparkles":
            return localized("sheet.quickCommands.symbolSparkles")
        case "hammer":
            return localized("sheet.quickCommands.symbolHammer")
        case "wrench.and.screwdriver":
            return localized("sheet.quickCommands.symbolTools")
        case "folder":
            return localized("sheet.quickCommands.symbolFolder")
        case "doc.text":
            return localized("sheet.quickCommands.symbolDocument")
        case "network":
            return localized("sheet.quickCommands.symbolNetwork")
        case "server.rack":
            return localized("sheet.quickCommands.symbolServer")
        case "shippingbox":
            return localized("sheet.quickCommands.symbolPackage")
        default:
            return symbol
        }
    }
}

private func quickCommandCategoryTint(_ id: String) -> Color {
    switch id {
    case QuickCommandCategory.codex.id:
        return LineyTheme.accent
    case QuickCommandCategory.claude.id:
        return LineyTheme.warning
    case QuickCommandCategory.cloud.id:
        return LineyTheme.localAccent
    case QuickCommandCategory.linux.id,
         QuickCommandCategory.system.id:
        return LineyTheme.secondaryText
    case QuickCommandCategory.files.id,
         QuickCommandCategory.archives.id:
        return LineyTheme.localAccent
    case QuickCommandCategory.search.id,
         QuickCommandCategory.text.id:
        return LineyTheme.success
    case QuickCommandCategory.processes.id,
         QuickCommandCategory.network.id:
        return LineyTheme.warning
    case QuickCommandCategory.complex.id:
        return LineyTheme.localAccent
    case QuickCommandCategory.git.id,
         QuickCommandCategory.homebrew.id,
         QuickCommandCategory.macos.id:
        return LineyTheme.accent
    default:
        return LineyTheme.accent
    }
}
