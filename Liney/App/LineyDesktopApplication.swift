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

    private let store = WorkspaceStore()
    private var windowController: NSWindowController?
    private var mainWindowBaseLevel: NSWindow.Level = .normal
    private var mainWindowBaseCollectionBehavior: NSWindow.CollectionBehavior = []

    public override init() {
        super.init()
    }

    public func launch() {
        LineyGhosttyBootstrap.initialize()
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        NSWindow.allowsAutomaticWindowTabbing = true

        if windowController == nil {
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
            window.tabbingIdentifier = Self.windowTabbingIdentifier
            window.isMovableByWindowBackground = false
            mainWindowBaseLevel = window.level
            mainWindowBaseCollectionBehavior = window.collectionBehavior

            let controller = NSWindowController(window: window)
            controller.shouldCascadeWindows = true
            windowController = controller
        }

        applyHotKeyWindowSettings(store.appSettings)
        presentMainWindow(ignoringOtherApps: false)

        Task { @MainActor in
            await store.loadIfNeeded()
        }
    }

    public func toggleCommandPalette() {
        store.dispatch(.toggleCommandPalette)
    }

    public func toggleOverview() {
        store.dispatch(.toggleOverview)
    }

    public func presentSettings() {
        store.presentSettings(for: store.selectedWorkspace)
    }

    public func checkForUpdates() {
        store.dispatch(.checkForUpdates)
    }

    public func shutdown() {
        LineyGlobalHotKeyMonitor.shared.unregister()
        store.stopSleepPrevention()
    }

    public func createTabInSelectedWorkspace() {
        guard let workspace = store.selectedWorkspace else { return }
        store.createTab(in: workspace)
    }

    public func closeSelectedTab() {
        guard let workspace = store.selectedWorkspace,
              workspace.tabs.count > 1,
              let activeTabID = workspace.activeTabID else {
            return
        }
        store.closeTab(in: workspace, tabID: activeTabID)
    }

    public func selectTab(number: Int) {
        guard (1...9).contains(number),
              let workspace = store.selectedWorkspace else { return }
        store.selectTab(in: workspace, index: number - 1)
    }

    public func selectNextTab() {
        guard let workspace = store.selectedWorkspace else { return }
        store.selectNextTab(in: workspace)
    }

    public func selectPreviousTab() {
        guard let workspace = store.selectedWorkspace else { return }
        store.selectPreviousTab(in: workspace)
    }

    func splitFocusedPane(axis: PaneSplitAxis) {
        guard let workspace = store.selectedWorkspace,
              workspace.sessionController.focusedPaneID != nil else {
            return
        }
        store.splitFocusedPane(in: workspace, axis: axis)
    }

    func duplicateFocusedPane() {
        guard let workspace = store.selectedWorkspace,
              workspace.sessionController.focusedPaneID != nil else {
            return
        }
        store.duplicateFocusedPane(in: workspace)
    }

    func toggleFocusedPaneZoom() {
        guard let workspace = store.selectedWorkspace,
              workspace.sessionController.focusedPaneID != nil else {
            return
        }
        store.toggleZoom(in: workspace)
    }

    func closeFocusedPane() {
        guard let workspace = store.selectedWorkspace,
              let paneID = workspace.sessionController.focusedPaneID else {
            return
        }
        store.closePane(in: workspace, paneID: paneID)
    }

    func refreshSelectedWorkspace() {
        store.refreshSelectedWorkspace()
    }

    func refreshAllRepositories() {
        store.dispatch(.refreshAllRepositories)
    }

    func openDiffWindow() {
        let workspace = store.selectedWorkspace
        let supportsDiff = workspace?.supportsRepositoryFeatures == true
        DiffWindowManager.shared.show(
            worktreePath: supportsDiff ? workspace?.activeWorktreePath : nil,
            branchName: workspace?.activeWorktree?.branchLabel ?? workspace?.currentBranch ?? "",
            emptyStateMessage: diffEmptyStateMessage(for: workspace, supportsDiff: supportsDiff)
        )
    }

    public var hasSelectedWorkspace: Bool {
        store.selectedWorkspace != nil
    }

    var selectedWorkspaceSupportsRepositoryFeatures: Bool {
        store.selectedWorkspace?.supportsRepositoryFeatures == true
    }

    var hasRepositoryWorkspaces: Bool {
        store.workspaces.contains(where: \.supportsRepositoryFeatures)
    }

    public var selectedWorkspaceTabCount: Int {
        store.selectedWorkspace?.tabs.count ?? 0
    }

    var isHotKeyWindowEnabled: Bool {
        store.appSettings.hotKeyWindowEnabled
    }

    var canCloseSelectedTab: Bool {
        guard let workspace = store.selectedWorkspace else { return false }
        return workspace.tabs.count > 1 && workspace.activeTabID != nil
    }

    var hasFocusedPane: Bool {
        store.selectedWorkspace?.sessionController.focusedPaneID != nil
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
        applyHotKeyWindowSettings(settings)
    }

    func reopenMainWindow() {
        presentMainWindow(ignoringOtherApps: true)
    }

    private func applyHotKeyWindowSettings(_ settings: AppSettings) {
        guard let window = windowController?.window else { return }

        if settings.hotKeyWindowEnabled {
            window.level = .floating
            window.collectionBehavior = mainWindowBaseCollectionBehavior.union([.moveToActiveSpace, .fullScreenAuxiliary])
            LineyGlobalHotKeyMonitor.shared.register(
                shortcut: settings.hotKeyWindowShortcut,
                action: { [weak self] in
                    self?.toggleHotKeyWindow()
                }
            )
        } else {
            window.level = mainWindowBaseLevel
            window.collectionBehavior = mainWindowBaseCollectionBehavior
            LineyGlobalHotKeyMonitor.shared.unregister()
        }
    }

    private func toggleHotKeyWindow() {
        guard let window = windowController?.window else { return }

        if window.isVisible {
            window.orderOut(nil)
            return
        }

        presentMainWindow(ignoringOtherApps: true)
    }

    private func presentMainWindow(ignoringOtherApps: Bool) {
        guard let window = windowController?.window else { return }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        NSApp.activate(ignoringOtherApps: ignoringOtherApps)
        windowController?.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
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
        var hotKeyID = EventHotKeyID(signature: OSType(0x4C4E5959), id: 1)
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
