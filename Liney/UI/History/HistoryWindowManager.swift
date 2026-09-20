//
//  HistoryWindowManager.swift
//  Liney
//
//  Author: everettjf
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class HistoryWindowManager: NSObject, NSWindowDelegate {
    static let shared = HistoryWindowManager()

    let state = HistoryWindowState()
    private var window: NSWindow?
    private var readinessSubscription: AnyCancellable?
    private var skipNextFocusRefresh = false
    private var localEventMonitor: Any?

    private override init() {}

    func show(for store: WorkspaceStore) {
        guard store.isWorkspaceStateReady else {
            show(worktreePath: nil, branchName: "", emptyStateMessage: LocalizationManager.shared.string("git.loading.workspace"))
            state.isLoadingCommits = true
            readinessSubscription = store.$isWorkspaceStateReady
                .filter { $0 }
                .first()
                .receive(on: RunLoop.main)
                .sink { [weak self, weak store] _ in
                    guard let self, let store else { return }
                    self.show(for: store)
                }
            Task { await store.loadIfNeeded() }
            return
        }
        let workspace = store.selectedWorkspace
        let supportsGit = workspace?.supportsRepositoryFeatures == true
        show(
            worktreePath: supportsGit ? workspace?.activeWorktreePath : nil,
            branchName: workspace?.activeWorktree?.branchLabel ?? workspace?.currentBranch ?? "",
            emptyStateMessage: emptyStateMessage(for: workspace)
        )
    }

    private func emptyStateMessage(for workspace: WorkspaceModel?) -> String {
        let localization = LocalizationManager.shared
        guard let workspace else { return localization.string("main.history.selectWorkspace") }
        if workspace.supportsRepositoryFeatures { return localization.string("main.history.noCommits") }
        return l10nFormat(localization.string("main.history.noContextFormat"), arguments: [workspace.name])
    }

    func show(worktreePath: String?, branchName: String, emptyStateMessage: String) {
        readinessSubscription = nil
        state.load(worktreePath: worktreePath, branchName: branchName, emptyStateMessage: emptyStateMessage)
        skipNextFocusRefresh = window?.isKeyWindow != true

        if let existingWindow = window {
            existingWindow.title = windowTitle(branchName: branchName)
            if existingWindow.isMiniaturized {
                existingWindow.deminiaturize(nil)
            }
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = HistoryWindowContentView(state: state)
            .preferredColorScheme(.dark)
        let hostingController = NSHostingController(rootView: contentView)
        // Window owns its frame; don't let the SwiftUI content's fitting size
        // drive window resizing (the default on recent macOS SDKs).
        hostingController.sizingOptions = []

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = windowTitle(branchName: branchName)
        newWindow.identifier = NSUserInterfaceItemIdentifier("liney.history")
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        newWindow.tabbingMode = .preferred
        newWindow.tabbingIdentifier = LineyDesktopApplication.sharedWindowTabbingIdentifier
        newWindow.toolbarStyle = .unifiedCompact
        newWindow.isReleasedWhenClosed = false
        newWindow.minSize = NSSize(width: 900, height: 520)
        newWindow.setFrameAutosaveName("LineyHistoryWindow")

        let hasSavedFrame = UserDefaults.standard.string(forKey: "NSWindow Frame LineyHistoryWindow") != nil
        if !hasSavedFrame {
            newWindow.setContentSize(NSSize(width: 1360, height: 800))
            newWindow.center()
        }

        newWindow.delegate = self
        newWindow.makeKeyAndOrderFront(nil)

        window = newWindow
        installWindowEventMonitor()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if skipNextFocusRefresh {
            skipNextFocusRefresh = false
            return
        }
        state.refresh()
    }

    func windowWillClose(_ notification: Notification) {
        readinessSubscription = nil
        window = nil
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }

    private func installWindowEventMonitor() {
        guard localEventMonitor == nil else { return }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, window == event.window else { return event }
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
               event.charactersIgnoringModifiers == "w" {
                window.performClose(nil)
                return nil
            }
            return event
        }
    }

    func showFileHistory(worktreePath: String?, branchName: String, filePath: String) {
        let emptyMessage = "No commit history for this file."
        state.load(worktreePath: worktreePath, branchName: branchName, emptyStateMessage: emptyMessage)
        state.showFileHistory(filePath: filePath)
        skipNextFocusRefresh = window?.isKeyWindow != true

        if let existingWindow = window {
            existingWindow.title = "File History — \(URL(fileURLWithPath: filePath).lastPathComponent)"
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }
        show(worktreePath: worktreePath, branchName: branchName, emptyStateMessage: emptyMessage)
    }

    private func windowTitle(branchName: String) -> String {
        branchName.isEmpty ? "Git History" : "Git History — \(branchName)"
    }
}
