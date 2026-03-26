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
    @State private var isCanvasPresented = false

    private var hasSelectedWorkspace: Bool {
        store.selectedWorkspace != nil
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
            return "Open Current Workspace in \(editor.editor.displayName)"
        }
        return "Open Current Workspace in an External Editor"
    }

    private var hapiHelpText: String {
        availableHAPIInstallation?.primaryActionHelpText ?? "Use HAPI in the current workspace"
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
                        .padding(4)
                }
                .accessibilityLabel("Toggle Sidebar")
                .help("Toggle Sidebar")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                HStack(spacing: 10) {
                    ToolbarSegmentedControl(
                    backgroundColor: LineyTheme.chromeBackground.opacity(0.96),
                    borderColor: LineyTheme.border,
                    leadingAction: { anchorView in
                        present(menu: makeQuickCommandMenu(), from: anchorView)
                    },
                    trailingAction: { _ in
                        store.presentQuickCommandEditor()
                    },
                    isLeadingDisabled: false,
                    isTrailingDisabled: false,
                    leadingAccessibilityLabel: "Insert Quick Command",
                    leadingHelp: hasSelectedSession
                        ? "Insert a Quick Command into the Focused Terminal"
                        : "Choose a Quick Command",
                    trailingAccessibilityLabel: "Edit Quick Commands",
                    trailingHelp: "Edit Quick Commands",
                    leadingContent: {
                        HStack(spacing: 6) {
                            ToolbarFeatureIcon(
                                systemName: "chevron.left.slash.chevron.right",
                                tint: LineyTheme.accent
                            )
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(LineyTheme.secondaryText)
                        }
                    },
                    trailingContent: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(LineyTheme.secondaryText)
                    }
                    )

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
                    trailingAccessibilityLabel: "Choose External Editor",
                    trailingHelp: "Choose an External Editor and Make It the Default",
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

                    if let hapiInstallation = availableHAPIInstallation {
                        ToolbarSegmentedControl(
                        backgroundColor: LineyTheme.chromeBackground.opacity(0.96),
                        borderColor: LineyTheme.border,
                        leadingAction: { _ in
                            store.performPrimaryHAPIAction()
                        },
                        trailingAction: { anchorView in
                            present(menu: makeHAPIMenu(using: hapiInstallation), from: anchorView)
                        },
                        isLeadingDisabled: !hasSelectedWorkspace,
                        isTrailingDisabled: !hasSelectedWorkspace,
                        leadingAccessibilityLabel: hapiInstallation.primaryActionTitle,
                        leadingHelp: hapiHelpText,
                        trailingAccessibilityLabel: "HAPI Actions",
                        trailingHelp: "HAPI Quick Start and Session Actions",
                        leadingContent: {
                            HStack(spacing: 6) {
                                ToolbarFeatureIcon(
                                    systemName: "dot.radiowaves.left.and.right",
                                    tint: hapiInstallation.authStatus.hasToken ? LineyTheme.success : LineyTheme.warning
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
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        dismissCanvas(restoreFocus: false)
                        store.isOverviewPresented.toggle()
                    }
                } label: {
                    Image(systemName: store.isOverviewPresented ? "building.2.fill" : "building.2")
                        .padding(4)
                }
                .accessibilityLabel("Overview")
                .help("Overview")

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
                        .padding(4)
                }
                .accessibilityLabel("Canvas")
                .help(isCanvasPresented ? "Hide Canvas" : "Show Canvas")

                Button {
                    openDiffWindow()
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                        .padding(4)
                }
                .accessibilityLabel("Diff")
                .help("Open Diff")

                Button {
                    store.dispatch(.toggleCommandPalette)
                } label: {
                    Image(systemName: "command")
                        .padding(4)
                }
                .accessibilityLabel("Command Palette")
                .help("Command Palette")

                Button {
                    guard let workspace = store.selectedWorkspace else { return }
                    store.splitFocusedPane(in: workspace, axis: .vertical)
                } label: {
                    Image(systemName: "rectangle.split.2x1.fill")
                        .padding(4)
                }
                .disabled(!hasFocusedPane)
                .accessibilityLabel("Split Right")
                .help("Split Right")

                Button {
                    guard let workspace = store.selectedWorkspace else { return }
                    store.splitFocusedPane(in: workspace, axis: .horizontal)
                } label: {
                    Image(systemName: "rectangle.split.1x2.fill")
                        .padding(4)
                }
                .disabled(!hasFocusedPane)
                .accessibilityLabel("Split Down")
                .help("Split Down")

                Button {
                    guard let workspace = store.selectedWorkspace else { return }
                    store.createTab(in: workspace)
                } label: {
                    Image(systemName: "plus.rectangle.on.rectangle")
                        .padding(4)
                }
                .disabled(!hasSelectedWorkspace)
                .accessibilityLabel("New Tab")
                .help("New Tab")

                Menu {
                    Button("Restart Focused Session") {
                        guard let workspace = store.selectedWorkspace else { return }
                        store.restartFocusedSession(in: workspace)
                    }
                    .disabled(!hasFocusedPane)

                    Button("Restart All Sessions") {
                        guard let workspace = store.selectedWorkspace else { return }
                        store.restartAllSessions(in: workspace)
                    }
                    .disabled(!hasSelectedWorkspace)

                    Button("Run Workspace Script") {
                        guard let workspace = store.selectedWorkspace else { return }
                        store.dispatch(.runWorkspaceScript(workspace.id))
                    }
                    .disabled(!(store.selectedWorkspace?.runScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false))

                    Button("Run Setup Script") {
                        guard let workspace = store.selectedWorkspace else { return }
                        store.dispatch(.runSetupScript(workspace.id))
                    }
                    .disabled(!(store.selectedWorkspace?.setupScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false))

                    Button("Run Preferred Workflow") {
                        guard let workspace = store.selectedWorkspace,
                              let workflow = workspace.preferredWorkflow else { return }
                        store.dispatch(.runWorkflow(workspace.id, workflow.id))
                    }
                    .disabled(store.selectedWorkspace?.preferredWorkflow == nil)

                    Divider()

                    Button("Equalize Splits") {
                        guard let workspace = store.selectedWorkspace else { return }
                        store.equalizeSplits(in: workspace)
                    }
                    .disabled(!hasSelectedWorkspace)

                    Button("Toggle Zoom") {
                        guard let workspace = store.selectedWorkspace else { return }
                        store.toggleZoom(in: workspace)
                    }
                    .disabled(!hasFocusedPane)

                    Button("Reset Layout") {
                        guard let workspace = store.selectedWorkspace else { return }
                        store.resetLayout(in: workspace)
                    }
                    .disabled(!hasSelectedWorkspace)

                    if selectedWorkspaceSupportsGit {
                        Divider()

                        Button("Create Worktree") {
                            guard let workspace = store.selectedWorkspace else { return }
                            store.presentCreateWorktree(for: workspace)
                        }
                        .disabled(!selectedWorkspaceSupportsGit)

                        Button("Refresh Repo") {
                            store.refreshSelectedWorkspace()
                        }
                        .disabled(!selectedWorkspaceSupportsGit)
                    }

                    Divider()

                    Button(store.isOverviewPresented ? "Close Workspace Overview" : "Open Workspace Overview") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            dismissCanvas(restoreFocus: false)
                            store.dispatch(.toggleOverview)
                        }
                    }

                    Button(isCanvasPresented ? "Hide Canvas" : "Show Canvas") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            store.isOverviewPresented = false
                            if isCanvasPresented {
                                dismissCanvas()
                            } else {
                                isCanvasPresented = true
                            }
                        }
                    }

                    Button("Open Diff") {
                        openDiffWindow()
                    }
                    Divider()

                    Button("Settings") {
                        store.presentSettings(for: store.selectedWorkspace)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .help("More Actions")
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
                store.renameWorkspace(id: request.workspaceID, to: name)
            }
        }
        .sheet(item: $store.createWorktreeRequest) { request in
            CreateWorktreeSheet(request: request) { draft in
                store.createWorktree(workspaceID: request.workspaceID, draft: draft)
            }
        }
        .sheet(item: $store.createSSHSessionRequest) { request in
            CreateSSHSessionSheet(request: request) { draft in
                store.createSSHSession(workspaceID: request.workspaceID, draft: draft)
            }
        }
        .sheet(item: $store.createAgentSessionRequest) { request in
            CreateAgentSessionSheet(request: request) { draft in
                store.createAgentSession(workspaceID: request.workspaceID, draft: draft)
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
        .sheet(item: $store.sidebarIconCustomizationRequest) { request in
            SidebarIconCustomizationSheet(request: request)
                .environmentObject(store)
        }
        .alert(item: $store.presentedError) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert(item: $store.pendingWorktreeSwitch) { request in
            Alert(
                title: Text("Switch worktree and restart panes?"),
                message: Text("Switching to \(request.targetName) restarts \(request.runningPaneCount) running pane(s) so their cwd matches the selected worktree and then \(request.requestedAction.displayLabel)."),
                primaryButton: .destructive(Text("Switch")) {
                    store.confirmPendingWorktreeSwitch()
                },
                secondaryButton: .cancel {
                    store.pendingWorktreeSwitch = nil
                }
            )
        }
        .confirmationDialog(
            store.pendingWorktreeRemoval?.itemCount == 1 ? "Remove worktree?" : "Remove selected worktrees?",
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
            Button("Remove", role: .destructive) {
                store.confirmPendingWorktreeRemoval()
            }
            if request.allowsForceRemove {
                Button("Force Remove", role: .destructive) {
                    store.confirmPendingWorktreeRemoval(force: true)
                }
            }
            Button("Cancel", role: .cancel) {
                store.pendingWorktreeRemoval = nil
            }
        } message: { request in
            Text(request.detailMessage)
        }
        .animation(.easeInOut(duration: 0.18), value: store.statusMessage?.id)
        .animation(.easeInOut(duration: 0.18), value: store.isCommandPalettePresented)
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

    private func diffEmptyStateMessage(for workspace: WorkspaceModel?, supportsDiff: Bool) -> String {
        guard let workspace else {
            return "Select a workspace to inspect changes."
        }
        if supportsDiff {
            return "Working directory is clean."
        }
        return "\(workspace.name) does not have a git diff context."
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
            menu.addDisabledItem(title: "Focus a terminal pane to insert a quick command")
            menu.addItem(.separator())
        }

        let recentCommands = store.recentQuickCommandPresets
        if !recentCommands.isEmpty {
            menu.addSectionHeader("Recent")
            for command in recentCommands {
                menu.addActionItem(
                    title: command.normalizedTitle,
                    imageSystemName: command.category.symbolName,
                    isEnabled: hasSelectedSession,
                    toolTip: command.command
                ) {
                    store.insertQuickCommand(command)
                }
            }
            menu.addItem(.separator())
        }

        let commandsByCategory = Dictionary(grouping: store.quickCommandPresets, by: \.category)
        for category in QuickCommandCategory.allCases {
            guard let commands = commandsByCategory[category], !commands.isEmpty else { continue }
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
            menu.addDisabledItem(title: "No quick commands configured")
            menu.addItem(.separator())
        }

        menu.addActionItem(title: "Edit Quick Commands…", imageSystemName: "slider.horizontal.3") {
            store.presentQuickCommandEditor()
        }

        return menu
    }

    private func makeExternalEditorMenu() -> NSMenu {
        let menu = NSMenu()

        if availableExternalEditors.isEmpty {
            menu.addDisabledItem(title: "No supported editors found")
        } else {
            menu.addSectionHeader("Open Workspace In")
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

        menu.addActionItem(title: "Settings…", imageSystemName: "gearshape") {
            store.presentSettings(for: store.selectedWorkspace)
        }

        return menu
    }

    private func makeHAPIMenu(using installation: HAPIInstallationStatus) -> NSMenu {
        let menu = NSMenu()

        menu.addDisabledItem(title: installation.menuStatusText)
        menu.addItem(.separator())

        menu.addActionItem(
            title: installation.primaryActionTitle,
            imageSystemName: installation.primaryAction == .launchSession ? "play.circle" : "dot.radiowaves.left.and.right"
        ) {
            store.performPrimaryHAPIAction()
        }

        if installation.primaryAction != .launchSession {
            menu.addActionItem(title: "Launch HAPI in Current Project", imageSystemName: "play.circle") {
                guard let workspace = store.selectedWorkspace else { return }
                store.launchHAPISession(workspaceID: workspace.id)
            }
        }

        if installation.primaryAction != .startHub {
            menu.addActionItem(title: "Start HAPI Hub (--relay)", imageSystemName: "dot.radiowaves.left.and.right") {
                guard let workspace = store.selectedWorkspace else { return }
                store.startHAPIHub(workspaceID: workspace.id)
            }
        }

        menu.addItem(.separator())
        menu.addActionItem(title: "Open HAPI Quick Start", imageSystemName: "book") {
            store.openHAPIQuickStart()
        }

        return menu
    }

    private func makeSleepPreventionMenu() -> NSMenu {
        let menu = NSMenu()

        if let session = store.sleepPreventionSession {
            menu.addDisabledItem(title: "Active: \(session.remainingDescription(relativeTo: store.sleepPreventionReferenceDate))")
            menu.addActionItem(title: "Stop Do Not Sleep", imageSystemName: "xmark.circle") {
                store.stopSleepPrevention()
            }
            menu.addItem(.separator())
        }

        menu.addSectionHeader("Prevent Sleep For")
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
