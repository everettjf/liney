//
//  HistoryWindowManager.swift
//  Liney
//
//  Author: everettjf
//

import AppKit
import SwiftUI

@MainActor
final class HistoryWindowManager: NSObject, NSWindowDelegate {
    static let shared = HistoryWindowManager()

    let state = HistoryWindowState()
    private var window: NSWindow?
    private var skipNextFocusRefresh = false
    private var localEventMonitor: Any?

    private override init() {}

    func show(worktreePath: String?, branchName: String, emptyStateMessage: String) {
        state.load(worktreePath: worktreePath, branchName: branchName, emptyStateMessage: emptyStateMessage)
        skipNextFocusRefresh = true

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

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = windowTitle(branchName: branchName)
        newWindow.identifier = NSUserInterfaceItemIdentifier("liney.history")
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        newWindow.tabbingMode = .preferred
        newWindow.tabbingIdentifier = LineyDesktopApplication.sharedWindowTabbingIdentifier
        newWindow.toolbarStyle = .unified
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
        skipNextFocusRefresh = true

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
