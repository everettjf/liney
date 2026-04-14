//
//  MainWindowView.swift
//  Liney
//
//  Author: everettjf
//

import AppKit
import ObjectiveC
import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @ObservedObject private var localization = LocalizationManager.shared
    @State private var isCanvasPresented = false

    private func localized(_ key: String) -> String {
        localization.string(key)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        l10nFormat(localized(key), locale: Locale.current, arguments: arguments)
    }

    private var hasSelectedWorkspace: Bool {
        store.selectedWorkspace != nil
    }

    private var uiScale: CGFloat {
        CGFloat(store.appSettings.uiScale)
    }

    private var hasFocusedPane: Bool {
        store.selectedWorkspace?.sessionController.focusedPaneID != nil
    }

    private var selectedWorkspaceSupportsGit: Bool {
        store.selectedWorkspace?.supportsRepositoryFeatures == true
    }

    private var hasSelectedSession: Bool {
        guard let workspace = store.selectedWorkspace else { return false }
        let targetPaneID = workspace.sessionController.focusedPaneID ?? workspace.paneOrder.first
        guard let targetPaneID else { return false }
        return workspace.sessionController.session(for: targetPaneID) != nil
    }

    private var availableExternalEditors: [ExternalEditorDescriptor] {
        store.availableExternalEditors
    }

    private var effectiveExternalEditor: ExternalEditorDescriptor? {
        store.effectiveExternalEditor
    }

    private var availableHAPIInstallation: HAPIInstallationStatus? {
        store.availableHAPIInstallation
    }

    private var externalEditorHelpText: String {
        if let editor = effectiveExternalEditor {
            return localizedFormat("main.toolbar.openCurrentWorkspaceInFormat", editor.editor.displayName)
        }
        return localized("main.toolbar.openCurrentWorkspaceInExternalEditor")
    }

    private var hapiHelpText: String {
        availableHAPIInstallation?.primaryActionHelpText ?? localized("main.hapi.defaultHelpText")
    }

    @ViewBuilder
    private func hapiToolbarControl(using installation: HAPIInstallationStatus) -> some View {
        ToolbarSegmentedControl(
            backgroundColor: LineyTheme.chromeBackground.opacity(0.96),
            borderColor: LineyTheme.border,
            leadingAction: { anchorView in
                present(menu: makeHAPIMenu(using: installation), from: anchorView)
            },
            trailingAction: { anchorView in
                present(menu: makeHAPIMenu(using: installation), from: anchorView)
            },
            isLeadingDisabled: !hasSelectedWorkspace,
            isTrailingDisabled: !hasSelectedWorkspace,
            leadingAccessibilityLabel: installation.primaryActionTitle,
            leadingHelp: hapiHelpText,
            trailingAccessibilityLabel: localized("main.hapi.actions"),
            trailingHelp: localized("main.hapi.quickStartActions"),
            leadingContent: {
                HStack(spacing: 6) {
                    ToolbarFeatureIcon(
                        systemName: "dot.radiowaves.left.and.right",
                        tint: LineyTheme.accent
                    )
                }
            },
            trailingContent: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(LineyTheme.secondaryText)
            }
        )
    }

    private var sleepPreventionIconName: String {
        store.sleepPreventionSession == nil ? "moon.zzz" : "moon.zzz.fill"
    }

    private var sleepPreventionSplitButtonBackground: Color {
        if store.sleepPreventionSession == nil {
            return LineyTheme.chromeBackground.opacity(0.96)
        }
        return LineyTheme.warning.opacity(0.14)
    }

    private var sleepPreventionSplitButtonBorder: Color {
        if store.sleepPreventionSession == nil {
            return LineyTheme.border
        }
        return LineyTheme.warning.opacity(0.42)
    }

    private func dismissCanvas(restoreFocus: Bool = true) {
        isCanvasPresented = false
        guard restoreFocus,
              let workspace = store.selectedWorkspace,
              let focusedPaneID = workspace.sessionController.focusedPaneID else {
            return
        }
        DispatchQueue.main.async {
            workspace.sessionController.focus(focusedPaneID)
        }
    }

    var body: some View {
        ZStack {
            NavigationSplitView {
                WorkspaceSidebarView()
                    .navigationSplitViewColumnWidth(min: 190, ideal: 240, max: 320)
            } detail: {
                if isCanvasPresented {
                    Color.clear
                } else {
                    WorkspaceDetailView()
                }
            }
            .navigationSplitViewStyle(.balanced)

            if store.isOverviewPresented {
                OverviewView {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        store.isOverviewPresented = false
                    }
                }
                .environmentObject(store)
                .transition(.opacity)
                .zIndex(1)
            }

            if isCanvasPresented {
                GlobalCanvasView {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        dismissCanvas()
                    }
                }
                .environmentObject(store)
                .transition(.opacity)
                .zIndex(1)
            }

            if store.isCommandPalettePresented {
                CommandPaletteView()
                    .environmentObject(store)
                    .transition(.opacity)
                    .zIndex(3)
            }

            VStack {
                if let statusMessage = store.statusMessage {
                    StatusBanner(message: statusMessage)
                        .padding(.top, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
            }
            .zIndex(2)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    NSApp.keyWindow?.firstResponder?.tryToPerform(
                        #selector(NSSplitViewController.toggleSidebar(_:)), with: nil
                    )
                } label: {
                    Image(systemName: "sidebar.leading")
                        .padding(4 * uiScale)
                }
                .scaleEffect(uiScale)
                .accessibilityLabel(localized("menu.view.toggleSidebar"))
                .help(localized("menu.view.toggleSidebar"))
            }

            ToolbarItemGroup(placement: .primaryAction) {
                HStack(spacing: 10) {
                    ToolbarSegmentedControl(
                    backgroundColor: LineyTheme.chromeBackground.opacity(0.96),
                    borderColor: LineyTheme.border,
                    leadingAction: { anchorView in
                        present(menu: makeQuickCommandMenu(), from: anchorView)
                    },
                    trailingAction: { anchorView in
                        present(menu: makeQuickCommandMenu(), from: anchorView)
                    },
                    isLeadingDisabled: false,
                    isTrailingDisabled: false,
                    leadingAccessibilityLabel: localized("main.toolbar.chooseQuickCommand"),
                    leadingHelp: localized("main.toolbar.chooseQuickCommand"),
                    trailingAccessibilityLabel: localized("main.toolbar.chooseQuickCommand"),
                    trailingHelp: localized("main.toolbar.chooseQuickCommand"),
                    leadingContent: {
                        HStack(spacing: 6) {
                            ToolbarFeatureIcon(
                                systemName: "chevron.left.slash.chevron.right",
                                tint: LineyTheme.accent
                            )
                        }
                    },
                    trailingContent: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(LineyTheme.secondaryText)
                    }
                    )

                    ToolbarSegmentedControl(
                    backgroundColor: LineyTheme.chromeBackground.opacity(0.96),
                    borderColor: LineyTheme.border,
                    leadingAction: { anchorView in
                        present(menu: makeWorkflowMenu(), from: anchorView)
                    },
                    trailingAction: { anchorView in
                        present(menu: makeWorkflowMenu(), from: anchorView)
                    },
                    isLeadingDisabled: !hasSelectedWorkspace,
                    isTrailingDisabled: !hasSelectedWorkspace,
                    leadingAccessibilityLabel: localized("main.toolbar.chooseWorkflow"),
                    leadingHelp: localized("main.toolbar.chooseWorkflow"),
                    trailingAccessibilityLabel: localized("main.toolbar.chooseWorkflow"),
                    trailingHelp: localized("main.toolbar.chooseWorkflow"),
                    leadingContent: {
                        HStack(spacing: 6) {
                            ToolbarFeatureIcon(
                                systemName: "play.rectangle.on.rectangle",
                                tint: LineyTheme.accent
                            )
                        }
                    },
                    trailingContent: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(LineyTheme.secondaryText)
                    }
                    )

                    if let hapiInstallation = availableHAPIInstallation, store.appSettings.showHAPIToolbarButton {
                        hapiToolbarControl(using: hapiInstallation)
                    }

                    ToolbarSegmentedControl(
                    backgroundColor: LineyTheme.chromeBackground.opacity(0.96),
                    borderColor: LineyTheme.border,
                    leadingAction: { _ in
                        store.openSelectedWorkspaceInPreferredExternalEditor()
                    },
                    trailingAction: { anchorView in
                        present(menu: makeExternalEditorMenu(), from: anchorView)
                    },
                    isLeadingDisabled: !hasSelectedWorkspace || effectiveExternalEditor == nil,
                    isTrailingDisabled: !hasSelectedWorkspace,
                    leadingAccessibilityLabel: externalEditorHelpText,
                    leadingHelp: externalEditorHelpText,
                    trailingAccessibilityLabel: localized("main.toolbar.chooseExternalEditor"),
                    trailingHelp: localized("main.toolbar.chooseExternalEditorDefault"),
                    leadingContent: {
                        HStack(spacing: 6) {
                            ToolbarFeatureIcon(
                                systemName: "arrow.up.forward.app.fill",
                                tint: LineyTheme.accent
                            )
                        }
                    },
                    trailingContent: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(LineyTheme.secondaryText)
                    }
                    )

                    ToolbarSegmentedControl(
                        backgroundColor: sleepPreventionSplitButtonBackground,
                        borderColor: sleepPreventionSplitButtonBorder,
                        leadingAction: { _ in
                            store.performPrimarySleepPreventionAction()
                        },
                        trailingAction: { anchorView in
                            present(menu: makeSleepPreventionMenu(), from: anchorView)
                        },
                        isLeadingDisabled: false,
                        isTrailingDisabled: false,
                        leadingAccessibilityLabel: store.sleepPreventionPrimaryActionLabel,
                        leadingHelp: store.sleepPreventionPrimaryActionHelpText,
                        trailingAccessibilityLabel: store.sleepPreventionStatusText,
                        trailingHelp: store.sleepPreventionStatusText,
                        leadingContent: {
                            ToolbarFeatureIcon(
                                systemName: sleepPreventionIconName,
                                tint: store.sleepPreventionSession == nil ? LineyTheme.secondaryText : LineyTheme.warning
                            )
                        },
                        trailingContent: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(LineyTheme.secondaryText)
                        }
                    )

                }
                .scaleEffect(uiScale)
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        dismissCanvas(restoreFocus: false)
                        store.isOverviewPresented.toggle()
                    }
                } label: {
                    Image(systemName: store.isOverviewPresented ? "building.2.fill" : "building.2")
                        .padding(4 * uiScale)
                }
                .scaleEffect(uiScale)
                .accessibilityLabel(localized("main.overview.title"))
                .help(localized("main.overview.title"))

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        store.isOverviewPresented = false
                        if isCanvasPresented {
                            dismissCanvas()
                        } else {
                            isCanvasPresented = true
                        }
                    }
                } label: {
                    Image(systemName: isCanvasPresented ? "square.grid.3x2.fill" : "square.grid.3x2")
                        .padding(4 * uiScale)
                }
                .scaleEffect(uiScale)
                .accessibilityLabel(localized("main.canvas.title"))
                .help(isCanvasPresented ? localized("main.canvas.hide") : localized("main.canvas.show"))

                Button {
                    openDiffWindow()
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                        .padding(4 * uiScale)
                }
                .scaleEffect(uiScale)
                .accessibilityLabel(localized("menu.view.openDiff"))
                .help(localized("menu.view.openDiff"))

                Button {
                    openHistoryWindow()
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .padding(4 * uiScale)
                }
                .scaleEffect(uiScale)
                .accessibilityLabel(localized("menu.view.openHistory"))
                .help(localized("menu.view.openHistory"))

                Button {
                    store.dispatch(.toggleCommandPalette)
                } label: {
                    Image(systemName: "command")
                        .padding(4 * uiScale)
                }
                .scaleEffect(uiScale)
                .accessibilityLabel(localized("menu.view.commandPalette"))
                .help(localized("menu.view.commandPalette"))

                Button {
                    guard let workspace = store.selectedWorkspace else { return }
                    store.splitFocusedPane(in: workspace, axis: .vertical)
                } label: {
                    Image(systemName: "rectangle.split.2x1.fill")
                        .padding(4 * uiScale)
                }
                .scaleEffect(uiScale)
                .disabled(!hasFocusedPane)
                .accessibilityLabel(localized("menu.file.splitRight"))
                .help(localized("menu.file.splitRight"))

                Button {
                    guard let workspace = store.selectedWorkspace else { return }
                    store.splitFocusedPane(in: workspace, axis: .horizontal)
                } label: {
                    Image(systemName: "rectangle.split.1x2.fill")
                        .padding(4 * uiScale)
                }
                .scaleEffect(uiScale)
                .disabled(!hasFocusedPane)
                .accessibilityLabel(localized("menu.file.splitDown"))
                .help(localized("menu.file.splitDown"))

                Button {
                    guard let workspace = store.selectedWorkspace else { return }
                    store.createTab(in: workspace)
                } label: {
                    Image(systemName: "plus.rectangle.on.rectangle")
                        .padding(4 * uiScale)
                }
                .scaleEffect(uiScale)
                .disabled(!hasSelectedWorkspace)
                .accessibilityLabel(localized("menu.file.newTab"))
                .help(localized("menu.file.newTab"))

                Menu {
                    Button(localized("main.menu.restartFocusedSession")) {
                        guard let workspace = store.selectedWorkspace else { return }
                        store.restartFocusedSession(in: workspace)
                    }
                    .disabled(!hasFocusedPane)

                    Button(localized("main.menu.restartAllSessions")) {
                        guard let workspace = store.selectedWorkspace else { return }
                        store.restartAllSessions(in: workspace)
                    }
                    .disabled(!hasSelectedWorkspace)

                    Button(localized("main.menu.runWorkspaceScript")) {
                        guard let workspace = store.selectedWorkspace else { return }
                        store.dispatch(.runWorkspaceScript(workspace.id))
                    }
                    .disabled(!(store.selectedWorkspace?.runScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false))

                    Button(localized("main.menu.runSetupScript")) {
                        guard let workspace = store.selectedWorkspace else { return }
                        store.dispatch(.runSetupScript(workspace.id))
                    }
                    .disabled(!(store.selectedWorkspace?.setupScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false))

                    Divider()

                    Button(localized("main.menu.equalizeSplits")) {
                        guard let workspace = store.selectedWorkspace else { return }
                        store.equalizeSplits(in: workspace)
                    }
                    .disabled(!hasSelectedWorkspace)

                    Button(localized("main.menu.toggleZoom")) {
                        guard let workspace = store.selectedWorkspace else { return }
                        store.toggleZoom(in: workspace)
                    }
                    .disabled(!hasFocusedPane)

                    Button(localized("main.menu.resetLayout")) {
                        guard let workspace = store.selectedWorkspace else { return }
                        store.resetLayout(in: workspace)
                    }
                    .disabled(!hasSelectedWorkspace)

                    Divider()

                    Button(localized("sidebar.menu.browseFiles")) {
                        guard let workspace = store.selectedWorkspace else { return }
                        store.presentWorkspaceFileBrowser(for: workspace)
                    }
                    .disabled(!hasSelectedWorkspace)

                    if selectedWorkspaceSupportsGit {
                        Button(localized("sheet.worktree.title")) {
                            guard let workspace = store.selectedWorkspace else { return }
                            store.presentCreateWorktree(for: workspace)
                        }
                        .disabled(!selectedWorkspaceSupportsGit)

                        Button(localized("main.menu.refreshRepo")) {
                            store.refreshSelectedWorkspace()
                        }
                        .disabled(!selectedWorkspaceSupportsGit)
                    }

                    Divider()

                    Button(store.isOverviewPresented ? localized("main.overview.close") : localized("main.overview.open")) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            dismissCanvas(restoreFocus: false)
                            store.dispatch(.toggleOverview)
                        }
                    }

                    Button(isCanvasPresented ? localized("main.canvas.hide") : localized("main.canvas.show")) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            store.isOverviewPresented = false
                            if isCanvasPresented {
                                dismissCanvas()
                            } else {
                                isCanvasPresented = true
                            }
                        }
                    }

                    Button(localized("menu.view.openDiff")) {
                        openDiffWindow()
                    }

                    Button(localized("menu.view.openHistory")) {
                        openHistoryWindow()
                    }

                    if let workspace = store.selectedWorkspace,
                       !workspace.remoteTargets.isEmpty {
                        Menu(localized("main.menu.remoteTargets")) {
                            ForEach(workspace.remoteTargets) { target in
                                Button(localizedFormat("main.menu.remoteShellFormat", target.name)) {
                                    store.dispatch(.openRemoteTargetShell(workspace.id, target.id))
                                }
                                Button(localizedFormat("main.menu.remoteBrowseFormat", target.name)) {
                                    store.dispatch(.browseRemoteTargetRepository(workspace.id, target.id))
                                }
                                Button(localizedFormat("main.menu.remoteCopyDestinationFormat", target.name)) {
                                    store.dispatch(.copyRemoteTargetDestination(workspace.id, target.id))
                                }
                                if target.ssh.remoteWorkingDirectory?.isEmpty == false {
                                    Button(localizedFormat("main.menu.remoteCopyPathFormat", target.name)) {
                                        store.dispatch(.copyRemoteTargetWorkingDirectory(workspace.id, target.id))
                                    }
                                }
                            }
                        }
                    }

                    Button(localized("menu.app.settings")) {
                        store.presentSettings(for: store.selectedWorkspace)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .scaleEffect(uiScale)
                .help(localized("main.menu.moreActions"))
            }
        }
        .task {
            await store.refreshHAPIIntegrationStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { @MainActor in
                await store.refreshHAPIIntegrationStatus()
            }
        }
        .onChange(of: store.selectedWorkspaceID) { _, newValue in
            if newValue == nil {
                isCanvasPresented = false
            }
        }
        .sheet(item: $store.renameWorkspaceRequest) { request in
            RenameWorkspaceSheet(request: request) { name in
                if request.isGroupCreation {
                    store.createWorkspaceGroup(named: name, workspaceIDs: request.groupWorkspaceIDs)
                } else if request.isGroupRename, let groupID = request.groupID {
                    store.renameWorkspaceGroup(groupID, to: name)
                } else {
                    store.renameWorkspace(id: request.workspaceID, to: name)
                }
            }
        }
        .sheet(item: $store.createWorktreeRequest) { request in
            CreateWorktreeSheet(request: request) { draft in
                store.createWorktree(workspaceID: request.workspaceID, draft: draft)
            }
        }
        .sheet(item: $store.editWorktreeNoteRequest) { request in
            EditWorktreeNoteSheet(request: request) { note in
                guard let workspace = store.workspaces.first(where: { $0.id == request.workspaceID }),
                      let worktree = workspace.worktrees.first(where: { $0.path == request.worktreePath }) else { return }
                store.setWorktreeNote(note.isEmpty ? nil : note, for: worktree, in: workspace)
            }
        }
        .sheet(item: $store.createSSHSessionRequest) { request in
            CreateSSHSessionSheet(request: request) { draft in
                store.createSSHSession(workspaceID: request.workspaceID, draft: draft)
            }
        }
        .sheet(item: $store.createSSHWorkspaceRequest) { _ in
            sshWorkspaceSheet
        }
        .sheet(item: $store.createAgentSessionRequest) { request in
            CreateAgentSessionSheet(request: request) { draft in
                store.createAgentSession(workspaceID: request.workspaceID, draft: draft)
            }
        }
        .sheet(item: $store.createRemoteWorkspaceRequest) { _ in
            CreateRemoteWorkspaceSheet { sshConfig, name in
                store.addRemoteWorkspace(sshConfig: sshConfig, name: name)
            }
        }
        .sheet(item: $store.settingsRequest) { request in
            SettingsSheet(request: request)
                .environmentObject(store)
        }
        .sheet(item: $store.quickCommandEditorRequest) { _ in
            QuickCommandEditorSheet()
                .environmentObject(store)
        }
        .sheet(item: $store.workflowEditorRequest) { request in
            WorkflowEditorSheet(workspaceID: request.workspaceID)
                .environmentObject(store)
        }

        .sheet(item: $store.workspaceFileBrowserRequest) { request in
            WorkspaceFileBrowserSheet(request: request)
                .environmentObject(store)
        }
        .sheet(item: $store.sidebarIconCustomizationRequest) { request in
            SidebarIconCustomizationSheet(request: request)
                .environmentObject(store)
        }
        .alert(item: $store.presentedError) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text(localized("common.ok")))
            )
        }
        .alert(item: $store.pendingWorktreeSwitch) { request in
            Alert(
                title: Text(localized("main.worktreeSwitch.title")),
                message: Text(localizedFormat("main.worktreeSwitch.messageFormat", request.targetName, request.runningPaneCount, request.requestedAction.displayLabel)),
                primaryButton: .destructive(Text(localized("main.worktreeSwitch.confirm"))) {
                    store.confirmPendingWorktreeSwitch()
                },
                secondaryButton: .cancel {
                    store.pendingWorktreeSwitch = nil
                }
            )
        }
        .confirmationDialog(
            store.pendingWorktreeRemoval?.itemCount == 1 ? localized("main.worktreeRemoval.singleTitle") : localized("main.worktreeRemoval.multiTitle"),
            isPresented: Binding(
                get: { store.pendingWorktreeRemoval != nil },
                set: { isPresented in
                    if !isPresented {
                        store.pendingWorktreeRemoval = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: store.pendingWorktreeRemoval
        ) { request in
            Button(localized("main.worktreeRemoval.remove"), role: .destructive) {
                store.confirmPendingWorktreeRemoval()
            }
            if request.allowsForceRemove {
                Button(localized("main.worktreeRemoval.forceRemove"), role: .destructive) {
                    store.confirmPendingWorktreeRemoval(force: true)
                }
            }
            Button(localized("common.cancel"), role: .cancel) {
                store.pendingWorktreeRemoval = nil
            }
        } message: { request in
            Text(request.detailMessage)
        }
        .animation(.easeInOut(duration: 0.18), value: store.statusMessage?.id)
        .animation(.easeInOut(duration: 0.18), value: store.isCommandPalettePresented)
    }

    @ViewBuilder
    private var sshWorkspaceSheet: some View {
        CreateSSHSessionSheet(
            request: CreateSSHSessionRequest(
                workspaceID: UUID(),
                workspaceName: "",
                defaultWorkingDirectory: "",
                remoteTargets: [],
                presets: [],
                preferredPresetID: nil
            )
        ) { draft in
            store.addSSHWorkspace(draft: draft)
        }
    }

    private func openDiffWindow() {
        let workspace = store.selectedWorkspace
        let supportsDiff = workspace?.supportsRepositoryFeatures == true
        DiffWindowManager.shared.show(
            worktreePath: supportsDiff ? workspace?.activeWorktreePath : nil,
            branchName: workspace?.activeWorktree?.branchLabel ?? workspace?.currentBranch ?? "",
            emptyStateMessage: diffEmptyStateMessage(for: workspace, supportsDiff: supportsDiff)
        )
    }

    private func openHistoryWindow() {
        let workspace = store.selectedWorkspace
        let supportsHistory = workspace?.supportsRepositoryFeatures == true
        HistoryWindowManager.shared.show(
            worktreePath: supportsHistory ? workspace?.activeWorktreePath : nil,
            branchName: workspace?.activeWorktree?.branchLabel ?? workspace?.currentBranch ?? "",
            emptyStateMessage: historyEmptyStateMessage(for: workspace, supportsHistory: supportsHistory)
        )
    }

    private func historyEmptyStateMessage(for workspace: WorkspaceModel?, supportsHistory: Bool) -> String {
        guard let workspace else {
            return localized("main.history.selectWorkspace")
        }
        if supportsHistory {
            return localized("main.history.noCommits")
        }
        return localizedFormat("main.history.noContextFormat", workspace.name)
    }

    private func diffEmptyStateMessage(for workspace: WorkspaceModel?, supportsDiff: Bool) -> String {
        guard let workspace else {
            return localized("main.diff.selectWorkspace")
        }
        if supportsDiff {
            return localized("main.diff.workingDirectoryClean")
        }
        return localizedFormat("main.diff.noContextFormat", workspace.name)
    }

    private func present(menu: NSMenu, from anchorView: NSView?) {
        guard let anchorView else { return }

        if let currentEvent = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: currentEvent, for: anchorView)
            return
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchorView.bounds.maxY + 6), in: anchorView)
    }

    private func makeQuickCommandMenu() -> NSMenu {
        let menu = NSMenu()

        if !hasSelectedSession {
            menu.addDisabledItem(title: localized("main.quickCommands.focusTerminal"))
            menu.addItem(.separator())
        }

        let recentCommands = store.recentQuickCommandPresets
        if !recentCommands.isEmpty {
            menu.addSectionHeader(localized("main.quickCommands.recent"))
            for command in recentCommands {
                let category = store.quickCommandCategoryMap[command.categoryID] ?? .fallbackCategory
                menu.addActionItem(
                    title: command.normalizedTitle,
                    imageSystemName: category.symbolName,
                    isEnabled: hasSelectedSession,
                    toolTip: command.command
                ) {
                    store.insertQuickCommand(command)
                }
            }
            menu.addItem(.separator())
        }

        let commandsByCategory = Dictionary(grouping: store.quickCommandPresets, by: \.categoryID)
        for category in QuickCommandCatalog.visibleCategories(
            commands: store.quickCommandPresets,
            categories: store.quickCommandCategories
        ) {
            guard let commands = commandsByCategory[category.id], !commands.isEmpty else { continue }
            menu.addSectionHeader(category.title)
            for command in commands {
                menu.addActionItem(
                    title: command.normalizedTitle,
                    imageSystemName: category.symbolName,
                    isEnabled: hasSelectedSession,
                    toolTip: command.command
                ) {
                    store.insertQuickCommand(command)
                }
            }
            menu.addItem(.separator())
        }

        if menu.items.last?.isSeparatorItem == true {
            menu.removeItem(at: menu.items.count - 1)
        }

        if store.quickCommandPresets.isEmpty {
            menu.addDisabledItem(title: localized("main.quickCommands.noneConfigured"))
            menu.addItem(.separator())
        }

        if !menu.items.isEmpty, menu.items.last?.isSeparatorItem == false {
            menu.addItem(.separator())
        }

        menu.addActionItem(title: localized("main.quickCommands.edit"), imageSystemName: "slider.horizontal.3") {
            store.presentQuickCommandEditor()
        }

        return menu
    }

    private func makeWorkflowMenu() -> NSMenu {
        let menu = NSMenu()

        guard let workspace = store.selectedWorkspace else {
            menu.addDisabledItem(title: localized("main.workflows.noneConfigured"))
            return menu
        }

        let workflows = workspace.workflows
        if workflows.isEmpty {
            menu.addDisabledItem(title: localized("main.workflows.noneConfigured"))
        } else {
            for workflow in workflows {
                let commandCount = workflow.commands.count
                let toolTip = commandCount > 0
                    ? localizedFormat("main.workflows.commandCountFormat", commandCount)
                    : nil
                menu.addActionItem(
                    title: workflow.name,
                    imageSystemName: "play.rectangle.on.rectangle",
                    isEnabled: true,
                    toolTip: toolTip
                ) {
                    store.dispatch(.runWorkflow(workspace.id, workflow.id))
                }
            }
        }

        menu.addItem(.separator())
        menu.addActionItem(title: localized("main.workflows.addWorkflow"), imageSystemName: "plus") {
            workspace.settings.workflows.append(
                WorkspaceWorkflow(name: localized("defaults.workflow.name"))
            )
            store.presentWorkflowEditor(for: workspace)
        }
        menu.addActionItem(title: localized("main.workflows.editWorkflows"), imageSystemName: "slider.horizontal.3") {
            store.presentWorkflowEditor(for: workspace)
        }

        return menu
    }

    private func makeExternalEditorMenu() -> NSMenu {
        let menu = NSMenu()

        if availableExternalEditors.isEmpty {
            menu.addDisabledItem(title: localized("main.externalEditor.noneFound"))
        } else {
            menu.addSectionHeader(localized("main.externalEditor.openWorkspaceIn"))
            for editor in availableExternalEditors {
                menu.addActionItem(
                    title: editor.editor.displayName,
                    state: effectiveExternalEditor?.editor == editor.editor ? .on : .off
                ) {
                    store.openSelectedWorkspaceInExternalEditor(editor.editor)
                }
            }
            menu.addItem(.separator())
        }

        menu.addActionItem(title: localized("menu.app.settings"), imageSystemName: "gearshape") {
            store.presentSettings(for: store.selectedWorkspace)
        }

        return menu
    }

    private func makeHAPIMenu(using installation: HAPIInstallationStatus) -> NSMenu {
        let menu = NSMenu()

        menu.addActionItem(title: localized("main.hapi.startHub"), imageSystemName: "dot.radiowaves.left.and.right") {
            guard let workspace = store.selectedWorkspace else { return }
            store.startHAPIHub(workspaceID: workspace.id)
        }
        menu.addActionItem(title: localized("main.hapi.startHubRelay"), imageSystemName: "dot.radiowaves.left.and.right") {
            guard let workspace = store.selectedWorkspace else { return }
            store.startHAPIHubRelay(workspaceID: workspace.id)
        }

        menu.addItem(.separator())
        menu.addActionItem(title: localized("main.hapi.claude"), imageSystemName: "play.circle") {
            guard let workspace = store.selectedWorkspace else { return }
            store.launchHAPISession(workspaceID: workspace.id)
        }
        menu.addActionItem(title: localized("main.hapi.codex"), imageSystemName: "terminal") {
            guard let workspace = store.selectedWorkspace else { return }
            store.launchHAPICodex(workspaceID: workspace.id)
        }
        menu.addActionItem(title: localized("main.hapi.cursor"), imageSystemName: "cursorarrow.rays") {
            guard let workspace = store.selectedWorkspace else { return }
            store.launchHAPICursor(workspaceID: workspace.id)
        }
        menu.addActionItem(title: localized("main.hapi.gemini"), imageSystemName: "sparkles") {
            guard let workspace = store.selectedWorkspace else { return }
            store.launchHAPIGemini(workspaceID: workspace.id)
        }
        menu.addActionItem(title: localized("main.hapi.opencode"), imageSystemName: "chevron.left.forwardslash.chevron.right") {
            guard let workspace = store.selectedWorkspace else { return }
            store.launchHAPIOpenCode(workspaceID: workspace.id)
        }

        menu.addItem(.separator())
        menu.addActionItem(title: localized("main.hapi.showSettings"), imageSystemName: "doc.text.magnifyingglass") {
            guard let workspace = store.selectedWorkspace else { return }
            store.showHAPISettings(workspaceID: workspace.id)
        }
        menu.addActionItem(title: localized("main.hapi.authStatus"), imageSystemName: "info.circle") {
            guard let workspace = store.selectedWorkspace else { return }
            store.showHAPIAuthStatus(workspaceID: workspace.id)
        }
        menu.addActionItem(title: localized("main.hapi.authLogin"), imageSystemName: "key") {
            guard let workspace = store.selectedWorkspace else { return }
            store.loginToHAPI(workspaceID: workspace.id)
        }
        menu.addActionItem(title: localized("main.hapi.authLogout"), imageSystemName: "rectangle.portrait.and.arrow.right") {
            guard let workspace = store.selectedWorkspace else { return }
            store.logoutFromHAPI(workspaceID: workspace.id)
        }

        if installation.cloudflaredExecutablePath != nil {
            menu.addItem(.separator())
            menu.addActionItem(title: localized("main.hapi.cloudflaredTunnel"), imageSystemName: "network") {
                guard let workspace = store.selectedWorkspace else { return }
                store.launchCloudflaredTunnel(workspaceID: workspace.id)
            }
            menu.addActionItem(title: localized("main.hapi.cloudflaredLogin"), imageSystemName: "person.badge.key") {
                guard let workspace = store.selectedWorkspace else { return }
                store.loginToCloudflaredTunnel(workspaceID: workspace.id)
            }
            menu.addActionItem(title: localized("main.hapi.cloudflaredRun"), imageSystemName: "bolt.horizontal.circle") {
                guard let workspace = store.selectedWorkspace else { return }
                store.runCloudflaredTunnel(workspaceID: workspace.id)
            }
        }

        menu.addItem(.separator())
        menu.addActionItem(title: localized("main.hapi.docs"), imageSystemName: "book") {
            guard let url = URL(string: "https://hapi.run/") else {
                return
            }
            NSWorkspace.shared.open(url)
        }
        if installation.cloudflaredExecutablePath != nil {
            menu.addActionItem(title: localized("main.hapi.cloudflareDocs"), imageSystemName: "book") {
                guard let url = URL(string: "https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/") else {
                    return
                }
                NSWorkspace.shared.open(url)
            }
        }

        return menu
    }

    private func makeSleepPreventionMenu() -> NSMenu {
        let menu = NSMenu()

        if let session = store.sleepPreventionSession {
            menu.addDisabledItem(title: localizedFormat("main.sleepPrevention.activeFormat", session.remainingDescription(relativeTo: store.sleepPreventionReferenceDate)))
            menu.addActionItem(title: localized("main.sleepPrevention.stop"), imageSystemName: "xmark.circle") {
                store.stopSleepPrevention()
            }
            menu.addItem(.separator())
        }

        menu.addSectionHeader(localized("main.sleepPrevention.preventFor"))
        for option in store.sleepPreventionOptions {
            menu.addActionItem(
                title: option.title,
                state: store.sleepPreventionQuickActionOption == option ? .on : .off
            ) {
                store.activateSleepPrevention(option)
            }
        }

        return menu
    }
}

private struct ToolbarSegmentedControl<LeadingContent: View, TrailingContent: View>: View {
    let backgroundColor: Color
    let borderColor: Color
    let leadingAction: (NSView?) -> Void
    let trailingAction: (NSView?) -> Void
    let isLeadingDisabled: Bool
    let isTrailingDisabled: Bool
    let leadingAccessibilityLabel: String
    let leadingHelp: String
    let trailingAccessibilityLabel: String
    let trailingHelp: String
    @ViewBuilder let leadingContent: () -> LeadingContent
    @ViewBuilder let trailingContent: () -> TrailingContent

    @State private var leadingAnchorView: NSView?
    @State private var trailingAnchorView: NSView?

    var body: some View {
        HStack(spacing: 0) {
            Button {
                leadingAction(leadingAnchorView)
            } label: {
                leadingContent()
                    .padding(.leading, 7)
                    .padding(.trailing, 8)
                    .frame(height: 22)
                    .contentShape(Rectangle())
                    .background(ToolbarAnchorView(anchorView: $leadingAnchorView))
            }
            .buttonStyle(.plain)
            .disabled(isLeadingDisabled)
            .accessibilityLabel(leadingAccessibilityLabel)
            .help(leadingHelp)

            Rectangle()
                .fill(borderColor.opacity(0.9))
                .frame(width: 1, height: 14)

            Button {
                trailingAction(trailingAnchorView)
            } label: {
                trailingContent()
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
                    .background(ToolbarAnchorView(anchorView: $trailingAnchorView))
            }
            .buttonStyle(.plain)
            .disabled(isTrailingDisabled)
            .accessibilityLabel(trailingAccessibilityLabel)
            .help(trailingHelp)
        }
        .background(backgroundColor, in: Capsule())
        .overlay(
            Capsule()
                .stroke(borderColor, lineWidth: 1)
        )
    }
}

private struct ToolbarAnchorView: NSViewRepresentable {
    @Binding var anchorView: NSView?

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            anchorView = view
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            anchorView = nsView
        }
    }
}

private var toolbarMenuActionAssociationKey: UInt8 = 0

private final class ToolbarMenuActionHandler: NSObject {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc
    func handleAction(_: Any?) {
        action()
    }
}

private extension NSMenu {
    func addSectionHeader(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        addItem(item)
    }

    func addDisabledItem(title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        addItem(item)
    }

    func addActionItem(
        title: String,
        imageSystemName: String? = nil,
        state: NSControl.StateValue = .off,
        isEnabled: Bool = true,
        toolTip: String? = nil,
        action: @escaping () -> Void
    ) {
        let handler = ToolbarMenuActionHandler(action: action)
        let item = NSMenuItem(title: title, action: #selector(ToolbarMenuActionHandler.handleAction(_:)), keyEquivalent: "")
        item.target = handler
        item.state = state
        item.isEnabled = isEnabled
        item.toolTip = toolTip
        if let imageSystemName {
            item.image = NSImage(systemSymbolName: imageSystemName, accessibilityDescription: title)
        }
        objc_setAssociatedObject(item, &toolbarMenuActionAssociationKey, handler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        addItem(item)
    }
}

private struct StatusBanner: View {
    let message: WorkspaceStatusMessage

    private var tint: Color {
        switch message.tone {
        case .neutral:
            return LineyTheme.secondaryText
        case .success:
            return LineyTheme.success
        case .warning:
            return LineyTheme.warning
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            Text(message.text)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(LineyTheme.canvasBackground.opacity(0.96), in: Capsule())
        .overlay(Capsule().stroke(LineyTheme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }
}
