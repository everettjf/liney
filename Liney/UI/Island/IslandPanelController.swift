//
//  IslandPanelController.swift
//  Liney
//
//  Author: everettjf
//

import AppKit
import SwiftUI

/// NSPanel subclass that disables automatic frame constraining so the
/// island can be positioned at the very top edge of any screen.
private class UnconstrainedPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }
}

@MainActor
final class IslandPanelController: NSObject, NSWindowDelegate {
    static let shared = IslandPanelController()

    let state = IslandNotificationState.shared
    weak var workspaceStore: WorkspaceStore?

    private var panel: NSPanel?
    private var localEventMonitor: Any?
    private var mouseEventMonitor: Any?
    private var localMouseMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var collapseTask: Task<Void, Never>?
    private var expandTask: Task<Void, Never>?

    /// The screen the island is pinned to. Defaults to the primary screen.
    private(set) var pinnedScreen: NSScreen?

    private let collapsedMinWidth: CGFloat = 120

    private var widthPreset: IslandWidthPreset {
        workspaceStore?.appSettings.dynamicIslandWidth ?? .standard
    }

    private var heightPreset: IslandHeightPreset {
        workspaceStore?.appSettings.dynamicIslandHeight ?? .standard
    }

    /// Detect notch dimensions on the pinned screen.
    /// Returns (width, height) of the notch, or (0, 0) if no notch.
    private var notchSize: (width: CGFloat, height: CGFloat) {
        guard let screen = pinnedScreen ?? NSScreen.screens.first else {
            return (0, 0)
        }
        let topInset = screen.safeAreaInsets.top
        guard topInset > 0 else { return (0, 0) }
        // Notch width = screen width minus the two auxiliary top areas
        let auxLeft = screen.auxiliaryTopLeftArea?.width ?? 0
        let auxRight = screen.auxiliaryTopRightArea?.width ?? 0
        let notchWidth = screen.frame.width - auxLeft - auxRight
        return (max(notchWidth, 0), topInset)
    }

    private var hasNotch: Bool { notchSize.height > 0 }

    /// Collapsed height: match notch height when present, otherwise 32pt.
    private var collapsedHeight: CGFloat {
        hasNotch ? max(notchSize.height, 32) : 32
    }

    /// Minimum width that covers the notch with some padding.
    private var notchAwareMinWidth: CGFloat {
        hasNotch ? notchSize.width + 40 : 0
    }

    private var collapsedMaxWidth: CGFloat {
        max(widthPreset.collapsedMaxWidth, notchAwareMinWidth)
    }
    private var expandedWidth: CGFloat {
        max(widthPreset.expandedWidth, notchAwareMinWidth)
    }
    private var expandedMaxHeight: CGFloat { heightPreset.expandedMaxHeight }

    private override init() {
        super.init()
        pinnedScreen = NSScreen.screens.first
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                // If the pinned screen was disconnected, fall back to primary
                if let pinned = self.pinnedScreen,
                   !NSScreen.screens.contains(where: { $0 == pinned }) {
                    self.pinnedScreen = NSScreen.screens.first
                }
                self.repositionPanel()
            }
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    func show() {
        if panel == nil {
            createPanel()
        }
        repositionPanel()
        panel?.orderFrontRegardless()
    }

    func hide() {
        state.isExpanded = false
        state.currentGroupID = nil
        panel?.orderOut(nil)
    }

    func toggle() {
        if panel?.isVisible == true {
            if state.isExpanded {
                state.isExpanded = false
                state.currentGroupID = nil
                repositionPanel()
            } else {
                hide()
            }
        } else {
            show()
        }
    }

    func navigateToItem(_ item: IslandNotificationItem) {
        WorkspaceNotificationCenter.shared.onNotificationTapped?(item.workspaceID, item.worktreePath)
        state.dismiss(id: item.id)
        if state.items.isEmpty && state.selectedTab == .notifications {
            hide()
        } else {
            repositionPanel()
        }
    }

    func navigateToWorkspace(_ workspace: WorkspaceModel) {
        WorkspaceNotificationCenter.shared.onNotificationTapped?(workspace.id, nil)
        state.isExpanded = false
        repositionPanel()
    }

    private func createPanel() {
        let contentView = IslandContentView(state: state, controller: self)
            .preferredColorScheme(.dark)
        let hostingController = NSHostingController(rootView: contentView)

        let targetScreen = pinnedScreen ?? NSScreen.screens.first
        let panel = UnconstrainedPanel(
            contentRect: targetScreen?.frame ?? .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false,
            screen: targetScreen
        )
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 8)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.contentViewController = hostingController
        panel.delegate = self

        self.panel = panel
        installEventMonitor()
        installMouseTracking()
    }

    func repositionPanel() {
        guard let panel else { return }

        let frame = panelFrame(expanded: state.isExpanded)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func collapsedWidth() -> CGFloat {
        let minNotch = notchAwareMinWidth

        if state.latestItem == nil {
            // "Liney" + pixel animation — use notch-aware width or 160pt
            return max(160, minNotch)
        }

        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let title = state.latestItem!.title
        let textWidth = (title as NSString).size(withAttributes: [.font: font]).width
        // icon(~14) + spacing(10) + text + spacing(4) + badge(~22) + horizontal padding(32)
        let hasBadge = state.badgeCount > 1
        let badgeWidth: CGFloat = hasBadge ? 26 : 0
        let totalWidth = 14 + 10 + textWidth + 4 + badgeWidth + 32
        let contentWidth = min(max(ceil(totalWidth), collapsedMinWidth), collapsedMaxWidth)
        return max(contentWidth, minNotch)
    }

    private func panelFrame(expanded: Bool) -> NSRect {
        let screen = pinnedScreen ?? NSScreen.screens.first ?? NSScreen.screens[0]
        let screenFrame = screen.frame

        let size: NSSize
        if expanded {
            size = NSSize(width: expandedWidth, height: expandedMaxHeight)
        } else {
            size = NSSize(width: collapsedWidth(), height: collapsedHeight)
        }

        // Center horizontally and push top edge above screen so the rounded corners
        // blend into the top edge, similar to a real Dynamic Island.
        let topOverlap: CGFloat = expanded ? 0 : 4
        let x = screenFrame.midX - size.width / 2
        let y = screenFrame.maxY - size.height + topOverlap

        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }

    private func installMouseTracking() {
        let handler: (NSEvent) -> Void = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkMousePosition()
            }
        }
        mouseEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: handler)
        // Also track when our app is in foreground
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.checkMousePosition()
            }
            return event
        }
    }

    private func checkMousePosition() {
        guard let panel, panel.isVisible else {
            collapseTask?.cancel()
            expandTask?.cancel()
            return
        }
        let mouseLocation = NSEvent.mouseLocation
        let panelFrame = panel.frame
        let hitArea = panelFrame.insetBy(dx: -20, dy: -20)
        let isInside = hitArea.contains(mouseLocation)

        if isInside {
            // Mouse entered — cancel any pending collapse, schedule expand
            collapseTask?.cancel()
            collapseTask = nil
            if !state.isExpanded && expandTask == nil {
                expandTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    self.state.isExpanded = true
                    self.repositionPanel()
                    self.expandTask = nil
                }
            }
        } else {
            // Mouse left — cancel any pending expand, schedule collapse
            expandTask?.cancel()
            expandTask = nil
            if state.isExpanded && collapseTask == nil {
                collapseTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    guard !Task.isCancelled else { return }
                    self.state.isExpanded = false
                    self.state.currentGroupID = nil
                    self.repositionPanel()
                    self.collapseTask = nil
                }
            }
        }
    }

    private func installEventMonitor() {
        guard localEventMonitor == nil else { return }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  let panel = self.panel,
                  panel.isVisible,
                  event.modifierFlags.contains(.command),
                  let prompt = self.state.items.first(where: { $0.prompt != nil })?.prompt else {
                return event
            }

            let keyNumber: Int?
            switch event.keyCode {
            case 18: keyNumber = 1
            case 19: keyNumber = 2
            case 20: keyNumber = 3
            case 21: keyNumber = 4
            case 23: keyNumber = 5
            default: keyNumber = nil
            }

            if let keyNumber, let option = prompt.options.first(where: { $0.id == keyNumber }) {
                if let item = self.state.items.first(where: { $0.prompt != nil }) {
                    Task { @MainActor in
                        _ = option.responseText
                        self.navigateToItem(item)
                    }
                }
                return nil
            }

            return event
        }
    }

    /// Cycle to the next screen.
    func cycleScreen() {
        let screens = NSScreen.screens
        guard screens.count > 1 else { return }
        if let current = pinnedScreen,
           let idx = screens.firstIndex(of: current) {
            pinnedScreen = screens[(idx + 1) % screens.count]
        } else {
            pinnedScreen = screens.first
        }
        repositionPanel()
    }

    var screenCount: Int {
        NSScreen.screens.count
    }

    var currentScreenIndex: Int {
        guard let pinned = pinnedScreen else { return 0 }
        return NSScreen.screens.firstIndex(of: pinned) ?? 0
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let mouseEventMonitor {
            NSEvent.removeMonitor(mouseEventMonitor)
            self.mouseEventMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
    }
}
