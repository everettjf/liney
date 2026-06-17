//
//  AgentOrchestrationWindowManager.swift
//  Liney
//
//  Author: everettjf
//

import AppKit
import SwiftUI

/// Owns the orchestration panel window. Modeled on `HistoryWindowManager`:
/// a single reusable NSWindow hosting a SwiftUI view, retained here. Runs a
/// light refresh timer only while the window is open.
@MainActor
final class AgentOrchestrationWindowManager: NSObject, NSWindowDelegate {
    static let shared = AgentOrchestrationWindowManager()

    private var window: NSWindow?
    private var store: AgentOrchestrationStore?
    private var refreshTimer: Timer?

    private override init() {}

    /// Opens (or re-focuses) the panel. `storesProvider` supplies the live
    /// workspace stores; `onReveal` jumps to the pane backing a row.
    func show(
        storesProvider: @escaping () -> [WorkspaceStore],
        onReveal: @escaping (AgentOrchestrationRow) -> Void
    ) {
        if let window {
            store?.refresh()
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            startRefreshTimer()
            return
        }

        let store = AgentOrchestrationStore(storesProvider: storesProvider)
        store.refresh()
        self.store = store

        let contentView = AgentOrchestrationView(
            store: store,
            onReveal: onReveal,
            onRefresh: { [weak store] in store?.refresh() }
        )
        .preferredColorScheme(.dark)

        let hostingController = NSHostingController(rootView: contentView)
        // Keep the window's frame independent of the SwiftUI content's fitting
        // size, so the panel doesn't resize as agent rows come and go.
        hostingController.sizingOptions = []
        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = "Agents"
        newWindow.identifier = NSUserInterfaceItemIdentifier("liney.orchestration")
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        newWindow.tabbingMode = .preferred
        newWindow.tabbingIdentifier = LineyDesktopApplication.sharedWindowTabbingIdentifier
        newWindow.toolbarStyle = .unifiedCompact
        newWindow.isReleasedWhenClosed = false
        newWindow.minSize = NSSize(width: 480, height: 360)
        newWindow.setFrameAutosaveName("LineyAgentOrchestrationWindow")

        let hasSavedFrame = UserDefaults.standard
            .string(forKey: "NSWindow Frame LineyAgentOrchestrationWindow") != nil
        if !hasSavedFrame {
            newWindow.setContentSize(NSSize(width: 560, height: 640))
            newWindow.center()
        }

        newWindow.delegate = self
        newWindow.makeKeyAndOrderFront(nil)
        window = newWindow
        startRefreshTimer()
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        // Agent detection is a process-tree scan; 2.5s keeps the panel live
        // without churning sysctl. Only runs while the window is open.
        let timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.store?.refresh()
            }
        }
        refreshTimer = timer
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func windowDidBecomeKey(_ notification: Notification) {
        store?.refresh()
        startRefreshTimer()
    }

    func windowDidResignKey(_ notification: Notification) {
        // Pause polling when the panel isn't in front.
        stopRefreshTimer()
    }

    func windowWillClose(_ notification: Notification) {
        stopRefreshTimer()
        window = nil
        store = nil
    }
}
