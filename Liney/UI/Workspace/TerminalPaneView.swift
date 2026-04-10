//
//  TerminalPaneView.swift
//  Liney
//
//  Author: everettjf
//

import SwiftUI

struct TerminalPaneView: View {
    private enum PaneHeaderDensity {
        case full
        case compact
        case minimal
    }

    @EnvironmentObject private var store: WorkspaceStore
    @ObservedObject private var localization = LocalizationManager.shared
    @ObservedObject var workspace: WorkspaceModel
    @ObservedObject var sessionController: WorkspaceSessionController
    @ObservedObject var session: ShellSession
    let paneID: UUID

    @FocusState private var searchFieldFocused: Bool
    @State private var isSearchPresented = false
    @State private var searchDraft = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var autoCloseTask: Task<Void, Never>?

    private var isFocused: Bool {
        sessionController.focusedPaneID == paneID
    }

    private func localized(_ key: String) -> String {
        localization.string(key)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        l10nFormat(localized(key), locale: Locale.current, arguments: arguments)
    }

    private var directoryLabel: String {
        session.effectiveWorkingDirectory.lastPathComponentValue
    }

    private var searchStatusLabel: String? {
        guard let total = session.surfaceStatus.searchTotal else { return nil }
        let selected = max(session.surfaceStatus.searchSelected ?? 0, 0)
        if total <= 0 {
            return localized("terminal.search.matchesZero")
        }
        return "\(selected + 1)/\(total)"
    }

    private var viewportLabel: String? {
        guard let progress = session.surfaceStatus.viewport?.progress else { return nil }
        if progress <= 0.02 {
            return localized("terminal.viewport.top")
        }
        if progress >= 0.98 {
            return localized("terminal.viewport.bottom")
        }
        return "\(Int(progress * 100))%"
    }

    private var paneHeaderStatusTag: (text: String, tone: PaneTag.Tone)? {
        if let exitCode = session.exitCode, session.lifecycle == .exited {
            return (localizedFormat("terminal.status.exitFormat", exitCode), .warning)
        }
        if isFocused {
            return (localized("terminal.status.active"), .accent)
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                paneHeaderContent(for: proxy.size.width)
            }
            .frame(height: 30)
            .padding(.horizontal, 10)
            .background(isFocused ? LineyTheme.panelRaised : LineyTheme.paneHeaderBackground)

            if isSearchPresented {
                PaneSearchBar(
                    text: $searchDraft,
                    isFocused: $searchFieldFocused,
                    resultLabel: searchStatusLabel,
                    onNext: {
                        workspace.focusPane(paneID)
                        session.searchNext()
                    },
                    onPrevious: {
                        workspace.focusPane(paneID)
                        session.searchPrevious()
                    },
                    onClose: closeSearch
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .background(isFocused ? LineyTheme.panelRaised : LineyTheme.paneHeaderBackground)
            }

            TerminalHostView(session: session, shouldRestoreFocus: isFocused)
                .id(session.lifecycle == .idle)
                .background(LineyTheme.paneBackground)
                .onTapGesture {
                    workspace.focusPane(paneID)
                }

            PaneStatusStrip(
                backendLabel: session.backendLabel,
                sizeLabel: "\(session.cols)x\(session.rows)",
                viewportLabel: viewportLabel,
                rendererHealthy: session.surfaceStatus.rendererHealthy,
                searchLabel: searchStatusLabel
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isFocused ? LineyTheme.accent.opacity(0.46) : LineyTheme.border, lineWidth: isFocused ? 1.2 : 1)
        )
        .background(LineyTheme.paneBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: Color.black.opacity(isFocused ? 0.12 : 0.05), radius: isFocused ? 5 : 2, y: 2)
        .contextMenu {
            Button(localized("terminal.menu.splitRight")) {
                workspace.focusPane(paneID)
                store.splitFocusedPane(in: workspace, axis: .vertical)
            }
            Button(localized("terminal.menu.splitDown")) {
                workspace.focusPane(paneID)
                store.splitFocusedPane(in: workspace, axis: .horizontal)
            }
            Divider()
            Button(localized("terminal.menu.duplicatePane")) {
                workspace.focusPane(paneID)
                store.duplicateFocusedPane(in: workspace)
            }
            Button(workspace.zoomedPaneID == paneID ? localized("terminal.menu.unzoomPane") : localized("terminal.menu.zoomPane")) {
                workspace.focusPane(paneID)
                store.toggleZoom(in: workspace, paneID: paneID)
            }
            Button(localized("terminal.menu.restartSession")) {
                workspace.focusPane(paneID)
                session.restart()
            }
            Button(localized("terminal.menu.find")) {
                workspace.focusPane(paneID)
                presentSearch()
            }
            Button(session.surfaceStatus.isReadOnly ? localized("terminal.menu.disableReadOnly") : localized("terminal.menu.enableReadOnly")) {
                workspace.focusPane(paneID)
                session.toggleReadOnly()
            }
            Button(localized("terminal.menu.clear")) {
                workspace.focusPane(paneID)
                session.clear()
            }
            Divider()
            Button(localized("terminal.menu.closePane")) {
                store.closePane(in: workspace, paneID: paneID)
            }
        }
        .onAppear {
            session.startIfNeeded()
            syncSearchState(with: session.surfaceStatus.searchQuery)
            scheduleAutoCloseIfNeeded()
        }
        .onChange(of: session.surfaceStatus.searchQuery) { _, newValue in
            syncSearchState(with: newValue)
        }
        .onChange(of: session.searchFocusRequestCount) { _, _ in
            presentSearch()
        }
        .onChange(of: session.lifecycle) { _, _ in
            scheduleAutoCloseIfNeeded()
        }
        .onChange(of: store.appSettings.autoClosePaneOnProcessExit) { _, _ in
            scheduleAutoCloseIfNeeded()
        }
        .onChange(of: searchDraft) { _, newValue in
            guard isSearchPresented else { return }
            scheduleSearchUpdate(newValue)
        }
        .onDisappear {
            searchTask?.cancel()
            searchTask = nil
            autoCloseTask?.cancel()
            autoCloseTask = nil
        }
    }

    private func paneHeaderDensity(for width: CGFloat) -> PaneHeaderDensity {
        switch width {
        case 340...:
            return .full
        case 250...:
            return .compact
        default:
            return .minimal
        }
    }

    @ViewBuilder
    private func paneHeaderContent(for width: CGFloat) -> some View {
        let density = paneHeaderDensity(for: width)

        HStack(spacing: 8) {
            Circle()
                .fill(session.hasActiveProcess ? LineyTheme.success : LineyTheme.warning)
                .frame(width: 7, height: 7)

            Text(session.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(LineyTheme.tertiaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            if density == .full {
                PaneTag(text: directoryLabel, tone: .neutral)
            }

            if density != .minimal,
               let statusTag = paneHeaderStatusTag,
               density == .full || statusTag.tone == .warning {
                PaneTag(text: statusTag.text, tone: statusTag.tone)
            }

            if density == .full, session.surfaceStatus.isReadOnly {
                PaneTag(text: localized("terminal.tag.readOnly"), tone: .warning)
            }

            Spacer(minLength: 6)

            HStack(spacing: 6) {
                PaneHeaderButton(systemName: "magnifyingglass") {
                    workspace.focusPane(paneID)
                    presentSearch()
                }

                PaneHeaderButton(systemName: session.surfaceStatus.isReadOnly ? "lock.fill" : "lock.open") {
                    workspace.focusPane(paneID)
                    session.toggleReadOnly()
                }

                PaneHeaderButton(systemName: workspace.zoomedPaneID == paneID ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") {
                    workspace.focusPane(paneID)
                    store.toggleZoom(in: workspace, paneID: paneID)
                }

                PaneHeaderButton(systemName: "xmark") {
                    store.closePane(in: workspace, paneID: paneID)
                }
            }
            .fixedSize()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func presentSearch() {
        isSearchPresented = true
        let selected = session.selectedText()
        if let selected, !selected.isEmpty {
            searchDraft = selected
        } else if searchDraft.isEmpty {
            searchDraft = session.surfaceStatus.searchQuery ?? ""
        }
        session.beginSearch()
        requestSearchFieldFocus()
    }

    private func closeSearch() {
        searchTask?.cancel()
        searchTask = nil
        isSearchPresented = false
        session.endSearch()
        searchFieldFocused = false
        Task { @MainActor in
            await Task.yield()
            session.focus()
        }
    }

    private func syncSearchState(with query: String?) {
        if let query {
            isSearchPresented = true
            if query != searchDraft {
                searchDraft = query
            }
            requestSearchFieldFocus()
        } else {
            searchTask?.cancel()
            searchTask = nil
            isSearchPresented = false
            searchFieldFocused = false
        }
    }

    private func requestSearchFieldFocus() {
        Task { @MainActor in
            await Task.yield()
            guard isSearchPresented else { return }
            searchFieldFocused = true
        }
    }

    private func scheduleSearchUpdate(_ query: String) {
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            session.updateSearch(query)
        }
    }

    private func scheduleAutoCloseIfNeeded() {
        autoCloseTask?.cancel()
        autoCloseTask = nil

        guard store.appSettings.autoClosePaneOnProcessExit,
              session.lifecycle == .exited else { return }

        autoCloseTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled,
                  store.appSettings.autoClosePaneOnProcessExit,
                  session.lifecycle == .exited else { return }
            store.closePane(in: workspace, paneID: paneID)
        }
    }
}

private struct PaneTag: View {
    enum Tone: Equatable {
        case neutral
        case accent
        case warning
    }

    let text: String
    let tone: Tone

    private var foreground: Color {
        switch tone {
        case .neutral:
            return LineyTheme.mutedText
        case .accent:
            return LineyTheme.accent
        case .warning:
            return LineyTheme.warning
        }
    }

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .fixedSize(horizontal: true, vertical: false)
            .background(LineyTheme.subtleFill, in: Capsule())
    }
}

private struct PaneHeaderButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .foregroundStyle(LineyTheme.secondaryText)
        .background(LineyTheme.subtleFill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

private struct PaneSearchBar: View {
    @ObservedObject private var localization = LocalizationManager.shared
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let resultLabel: String?
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onClose: () -> Void

    private func localized(_ key: String) -> String {
        localization.string(key)
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField(localized("terminal.search.placeholder"), text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .focused(isFocused)
                .onExitCommand(perform: onClose)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(LineyTheme.subtleFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            if let resultLabel {
                PaneTag(text: resultLabel, tone: .neutral)
            }

            PaneHeaderButton(systemName: "chevron.up") {
                onPrevious()
            }

            PaneHeaderButton(systemName: "chevron.down") {
                onNext()
            }

            PaneHeaderButton(systemName: "xmark") {
                onClose()
            }
        }
    }
}

private struct PaneStatusStrip: View {
    @ObservedObject private var localization = LocalizationManager.shared
    let backendLabel: String
    let sizeLabel: String
    let viewportLabel: String?
    let rendererHealthy: Bool
    let searchLabel: String?

    private func localized(_ key: String) -> String {
        localization.string(key)
    }

    var body: some View {
        HStack(spacing: 8) {
            PaneTag(text: backendLabel, tone: .neutral)
            PaneTag(text: sizeLabel, tone: .neutral)

            if let viewportLabel {
                PaneTag(text: viewportLabel, tone: .neutral)
            }

            if let searchLabel {
                PaneTag(text: searchLabel, tone: .accent)
            }

            if !rendererHealthy {
                PaneTag(text: localized("terminal.status.renderer"), tone: .warning)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(LineyTheme.panelRaised.opacity(0.72))
    }
}
