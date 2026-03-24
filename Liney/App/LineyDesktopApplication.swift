//
//  LineyDesktopApplication.swift
//  Liney
//
//  Author: everettjf
//

import AppKit
import Carbon
import SwiftUI

@MainActor
public final class LineyDesktopApplication: NSObject {
    private static let windowTabbingIdentifier = "dev.liney.window"

    private final class WindowContext: NSObject, NSWindowDelegate {
        let store: WorkspaceStore
        let controller: NSWindowController
        var persistsWorkspaceState: Bool
        let baseLevel: NSWindow.Level
        let baseCollectionBehavior: NSWindow.CollectionBehavior
        weak var owner: LineyDesktopApplication?

        init(
            store: WorkspaceStore,
            persistsWorkspaceState: Bool,
            owner: LineyDesktopApplication
        ) {
            self.store = store
            self.persistsWorkspaceState = persistsWorkspaceState
            self.owner = owner

            let host = NSHostingController(
                rootView: MainWindowView()
                    .environmentObject(store)
                    .preferredColorScheme(.dark)
            )

            let window = NSWindow(contentViewController: host)
            window.title = "Liney"
            window.setContentSize(NSSize(width: 1440, height: 920))
            window.minSize = NSSize(width: 1120, height: 720)
            window.center()
            window.isOpaque = false
            window.backgroundColor = NSColor(calibratedRed: 0.055, green: 0.06, blue: 0.075, alpha: 1)
            window.styleMask.remove(.fullSizeContentView)
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = false
            window.toolbarStyle = .unifiedCompact
            window.tabbingMode = .preferred
            window.tabbingIdentifier = LineyDesktopApplication.windowTabbingIdentifier
            window.isMovableByWindowBackground = false

            baseLevel = window.level
            baseCollectionBehavior = window.collectionBehavior

            let controller = NSWindowController(window: window)
            controller.shouldCascadeWindows = true
            self.controller = controller

            super.init()

            window.delegate = self
        }

        var window: NSWindow? {
            controller.window
        }

        func present(ignoringOtherApps: Bool, activatesApplication: Bool = true) {
            guard let window else { return }

            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            if activatesApplication {
                NSApp.activate(ignoringOtherApps: ignoringOtherApps)
            }
            controller.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
        }

        func windowWillClose(_ notification: Notification) {
            owner?.removeWindowContext(self)
        }
    }

    private var windowContexts: [WindowContext] = []
    private var hotKeyWindowSettings = AppSettings()
    private var lastPrimaryWindowState: PersistedWorkspaceState?

    public override init() {
        super.init()
    }

    public func launch() {
        LineyGhosttyBootstrap.initialize()
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        NSWindow.allowsAutomaticWindowTabbing = true

        let context = ensurePrimaryWindowContext(
            initialState: nil,
            initialAppSettings: nil
        )
        syncWindowPresentation()
        DispatchQueue.main.async {
            context.present(ignoringOtherApps: false, activatesApplication: false)
        }

        Task { @MainActor in
            await loadWindowContextIfNeeded(context, updateHotKeySettings: true)
        }
    }

    public func toggleCommandPalette() {
        activeStore?.dispatch(.toggleCommandPalette)
    }

    public func toggleOverview() {
        activeStore?.dispatch(.toggleOverview)
    }

    public func presentSettings() {
        guard let store = activeStore else { return }
        store.presentSettings(for: store.selectedWorkspace)
    }

    public func checkForUpdates() {
        activeStore?.dispatch(.checkForUpdates)
    }

    public func shutdown() {
        LineyGlobalHotKeyMonitor.shared.unregister()
        for context in windowContexts {
            context.store.stopSleepPrevention()
        }
    }

    public func createNewWindow() {
        let context = makeWindowContext(
            persistsWorkspaceState: windowContexts.isEmpty,
            initialState: activeStore?.currentStateSnapshot() ?? lastPrimaryWindowState,
            initialAppSettings: activeStore?.appSettings ?? hotKeyWindowSettings
        )
        windowContexts.append(context)
        syncWindowPresentation()
        context.present(ignoringOtherApps: true)

        Task { @MainActor in
            await loadWindowContextIfNeeded(context, updateHotKeySettings: false)
        }
    }

    public func createTabInSelectedWorkspace() {
        guard let store = activeStore,
              let workspace = store.selectedWorkspace else { return }
        store.createTab(in: workspace)
    }

    public func closeSelectedTab() {
        guard let store = activeStore,
              let workspace = store.selectedWorkspace,
              workspace.tabs.count > 1,
              let activeTabID = workspace.activeTabID else {
            return
        }
        store.closeTab(in: workspace, tabID: activeTabID)
    }

    public func selectTab(number: Int) {
        guard (1...9).contains(number),
              let store = activeStore,
              let workspace = store.selectedWorkspace else { return }
        store.selectTab(in: workspace, index: number - 1)
    }

    public func selectNextTab() {
        guard let store = activeStore,
              let workspace = store.selectedWorkspace else { return }
        store.selectNextTab(in: workspace)
    }

    public func selectPreviousTab() {
        guard let store = activeStore,
              let workspace = store.selectedWorkspace else { return }
        store.selectPreviousTab(in: workspace)
    }

    func splitFocusedPane(axis: PaneSplitAxis) {
        guard let store = activeStore,
              let workspace = store.selectedWorkspace,
              workspace.sessionController.focusedPaneID != nil else {
            return
        }
        store.splitFocusedPane(in: workspace, axis: axis)
    }

    func duplicateFocusedPane() {
        guard let store = activeStore,
              let workspace = store.selectedWorkspace,
              workspace.sessionController.focusedPaneID != nil else {
            return
        }
        store.duplicateFocusedPane(in: workspace)
    }

    func toggleFocusedPaneZoom() {
        guard let store = activeStore,
              let workspace = store.selectedWorkspace,
              workspace.sessionController.focusedPaneID != nil else {
            return
        }
        store.toggleZoom(in: workspace)
    }

    func closeFocusedPane() {
        guard let store = activeStore,
              let workspace = store.selectedWorkspace,
              let paneID = workspace.sessionController.focusedPaneID else {
            return
        }
        store.closePane(in: workspace, paneID: paneID)
    }

    func refreshSelectedWorkspace() {
        activeStore?.refreshSelectedWorkspace()
    }

    func refreshAllRepositories() {
        activeStore?.dispatch(.refreshAllRepositories)
    }

    func openDiffWindow() {
        let workspace = activeStore?.selectedWorkspace
        let supportsDiff = workspace?.supportsRepositoryFeatures == true
        DiffWindowManager.shared.show(
            worktreePath: supportsDiff ? workspace?.activeWorktreePath : nil,
            branchName: workspace?.activeWorktree?.branchLabel ?? workspace?.currentBranch ?? "",
            emptyStateMessage: diffEmptyStateMessage(for: workspace, supportsDiff: supportsDiff)
        )
    }

    public var hasSelectedWorkspace: Bool {
        activeStore?.selectedWorkspace != nil
    }

    var selectedWorkspaceSupportsRepositoryFeatures: Bool {
        activeStore?.selectedWorkspace?.supportsRepositoryFeatures == true
    }

    var hasRepositoryWorkspaces: Bool {
        activeStore?.workspaces.contains(where: \.supportsRepositoryFeatures) == true
    }

    public var selectedWorkspaceTabCount: Int {
        activeStore?.selectedWorkspace?.tabs.count ?? 0
    }

    var isHotKeyWindowEnabled: Bool {
        hotKeyWindowSettings.hotKeyWindowEnabled
    }

    var confirmQuitWhenCommandsRunning: Bool {
        hotKeyWindowSettings.confirmQuitWhenCommandsRunning
    }

    var needsConfirmQuit: Bool {
        LineyGhosttyRuntime.shared.needsConfirmQuit || quitConfirmationSessionCount > 0
    }

    var quitConfirmationSessionCount: Int {
        windowContexts.reduce(0) { $0 + $1.store.quitConfirmationSessionCount }
    }

    var canCloseSelectedTab: Bool {
        guard let workspace = activeStore?.selectedWorkspace else { return false }
        return workspace.tabs.count > 1 && workspace.activeTabID != nil
    }

    var hasFocusedPane: Bool {
        activeStore?.selectedWorkspace?.sessionController.focusedPaneID != nil
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

    static var sharedWindowTabbingIdentifier: String {
        windowTabbingIdentifier
    }

    func updateHotKeyWindowSettings(_ settings: AppSettings) {
        hotKeyWindowSettings = settings
        syncWindowPresentation()
    }

    func reopenMainWindow() {
        let context = ensurePrimaryWindowContext(
            initialState: lastPrimaryWindowState,
            initialAppSettings: hotKeyWindowSettings
        )
        syncWindowPresentation()
        context.present(ignoringOtherApps: true)

        Task { @MainActor in
            await loadWindowContextIfNeeded(context, updateHotKeySettings: true)
        }
    }

    private var primaryWindowContext: WindowContext? {
        windowContexts.first(where: \.persistsWorkspaceState)
    }

    private var activeWindowContext: WindowContext? {
        if let keyWindow = NSApp.keyWindow,
           let context = context(for: keyWindow) {
            return context
        }
        if let mainWindow = NSApp.mainWindow,
           let context = context(for: mainWindow) {
            return context
        }
        return primaryWindowContext ?? windowContexts.first
    }

    private var activeStore: WorkspaceStore? {
        activeWindowContext?.store
    }

    private func ensurePrimaryWindowContext(
        initialState: PersistedWorkspaceState?,
        initialAppSettings: AppSettings?
    ) -> WindowContext {
        if let primaryWindowContext {
            return primaryWindowContext
        }

        let context = makeWindowContext(
            persistsWorkspaceState: true,
            initialState: initialState,
            initialAppSettings: initialAppSettings
        )
        windowContexts.append(context)
        return context
    }

    private func makeWindowContext(
        persistsWorkspaceState: Bool,
        initialState: PersistedWorkspaceState?,
        initialAppSettings: AppSettings?
    ) -> WindowContext {
        let store = WorkspaceStore(
            initialWorkspaceState: initialState,
            initialAppSettings: initialAppSettings,
            persistsWorkspaceState: persistsWorkspaceState
        )
        return WindowContext(
            store: store,
            persistsWorkspaceState: persistsWorkspaceState,
            owner: self
        )
    }

    private func context(for window: NSWindow) -> WindowContext? {
        windowContexts.first { $0.window === window }
    }

    private func removeWindowContext(_ context: WindowContext) {
        let wasPrimary = context.persistsWorkspaceState
        if wasPrimary {
            lastPrimaryWindowState = context.store.currentStateSnapshot()
        }
        windowContexts.removeAll { $0 === context }

        if wasPrimary, let promotedContext = windowContexts.first {
            promotedContext.persistsWorkspaceState = true
            promotedContext.store.setWorkspaceStatePersistenceEnabled(true)
        }

        syncWindowPresentation()
    }

    private func syncWindowPresentation() {
        if hotKeyWindowSettings.hotKeyWindowEnabled {
            LineyGlobalHotKeyMonitor.shared.register(
                shortcut: hotKeyWindowSettings.hotKeyWindowShortcut,
                action: { [weak self] in
                    self?.toggleHotKeyWindow()
                }
            )
        } else {
            LineyGlobalHotKeyMonitor.shared.unregister()
        }

        for context in windowContexts {
            guard let window = context.window else { continue }

            if hotKeyWindowSettings.hotKeyWindowEnabled, context.persistsWorkspaceState {
                window.level = .floating
                window.collectionBehavior = context.baseCollectionBehavior.union([.moveToActiveSpace, .fullScreenAuxiliary])
            } else {
                window.level = context.baseLevel
                window.collectionBehavior = context.baseCollectionBehavior
            }
        }
    }

    private func toggleHotKeyWindow() {
        let context = ensurePrimaryWindowContext(
            initialState: lastPrimaryWindowState,
            initialAppSettings: hotKeyWindowSettings
        )
        syncWindowPresentation()

        guard let window = context.window else { return }

        if window.isVisible, NSApp.keyWindow === window {
            window.orderOut(nil)
            return
        }

        context.present(ignoringOtherApps: true)

        Task { @MainActor in
            await loadWindowContextIfNeeded(context, updateHotKeySettings: true)
        }
    }

    private func loadWindowContextIfNeeded(_ context: WindowContext, updateHotKeySettings: Bool) async {
        await context.store.loadIfNeeded()
        if updateHotKeySettings {
            hotKeyWindowSettings = context.store.appSettings
        }
        syncWindowPresentation()
    }
}

@MainActor
private final class LineyGlobalHotKeyMonitor {
    static let shared = LineyGlobalHotKeyMonitor()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var action: (() -> Void)?

    private init() {
        installEventHandlerIfNeeded()
    }

    func register(shortcut: StoredShortcut, action: @escaping () -> Void) {
        unregister()
        self.action = action
        installEventHandlerIfNeeded()

        guard let keyCode = shortcut.carbonKeyCode else { return }
        let hotKeyID = EventHotKeyID(signature: OSType(0x4C4E5959), id: 1)
        RegisterEventHotKey(
            keyCode,
            shortcut.carbonModifierFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        action = nil
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                Task { @MainActor in
                    LineyGlobalHotKeyMonitor.shared.action?()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
    }
}
