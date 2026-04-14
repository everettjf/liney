//
//  DiffWindowManager.swift
//  Liney
//
//  Author: everettjf
//

import AppKit
import SwiftUI
import WebKit

@MainActor
final class DiffWindowManager: NSObject, NSWindowDelegate {
    static let shared = DiffWindowManager()

    let state = DiffWindowState()
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

        let contentView = DiffWindowContentView(state: state)
            .preferredColorScheme(.dark)
        let hostingController = NSHostingController(rootView: contentView)

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = windowTitle(branchName: branchName)
        newWindow.identifier = NSUserInterfaceItemIdentifier("liney.diff")
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        newWindow.tabbingMode = .preferred
        newWindow.tabbingIdentifier = LineyDesktopApplication.sharedWindowTabbingIdentifier
        newWindow.toolbarStyle = .unifiedCompact
        newWindow.isReleasedWhenClosed = false
        newWindow.minSize = NSSize(width: 760, height: 520)
        newWindow.setFrameAutosaveName("LineyDiffWindow")

        let hasSavedFrame = UserDefaults.standard.string(forKey: "NSWindow Frame LineyDiffWindow") != nil
        if !hasSavedFrame {
            newWindow.setContentSize(NSSize(width: 1180, height: 760))
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

    func applyZoom(_ level: Double) {
        guard let window else { return }
        findWKWebViews(in: window.contentView).forEach { webView in
            webView.pageZoom = level
        }
    }

    private func adjustZoom(by delta: Double) {
        let current = UserDefaults.standard.double(forKey: "liney.diff.zoom")
        let currentLevel = current == 0 ? 1.0 : current
        let newLevel = min(3.0, max(0.5, currentLevel + delta))
        setZoom(newLevel)
    }

    private func setZoom(_ level: Double) {
        UserDefaults.standard.set(level, forKey: "liney.diff.zoom")
        applyZoom(level)
    }

    private func findWKWebViews(in view: NSView?) -> [WKWebView] {
        guard let view else { return [] }
        var results: [WKWebView] = []
        if let webView = view as? WKWebView {
            results.append(webView)
        }
        for subview in view.subviews {
            results.append(contentsOf: findWKWebViews(in: subview))
        }
        return results
    }

    private func installWindowEventMonitor() {
        guard localEventMonitor == nil else { return }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, window == event.window else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == .command else { return event }

            switch event.charactersIgnoringModifiers {
            case "w":
                window.performClose(nil)
                return nil
            case "+", "=":
                self.adjustZoom(by: 0.1)
                return nil
            case "-":
                self.adjustZoom(by: -0.1)
                return nil
            case "0":
                self.setZoom(1.0)
                return nil
            default:
                return event
            }
        }
    }

    private func windowTitle(branchName: String) -> String {
        branchName.isEmpty ? "Diff" : "Diff — \(branchName)"
    }
}
