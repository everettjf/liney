//
//  IslandPanelController.swift
//  Liney
//
//  Author: everettjf
//

import AppKit
import SwiftUI

@MainActor
final class IslandPanelController: NSObject, NSWindowDelegate {
    static let shared = IslandPanelController()

    let state = IslandNotificationState.shared
    weak var workspaceStore: WorkspaceStore?

    private var panel: NSPanel?
    private var localEventMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var autoDismissTask: Task<Void, Never>?

    private let collapsedSize = NSSize(width: 340, height: 38)
    private let expandedWidth: CGFloat = 480
    private let expandedMaxHeight: CGFloat = 520

    private override init() {
        super.init()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.repositionPanel()
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
        scheduleAutoDismiss()
    }

    func hide() {
        autoDismissTask?.cancel()
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

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: collapsedSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.contentViewController = hostingController
        panel.delegate = self

        self.panel = panel
        installEventMonitor()
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

    private func panelFrame(expanded: Bool) -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens.first ?? NSScreen.screens[0]
        let screenFrame = screen.frame

        let hasNotch: Bool
        if let _ = screen.auxiliaryTopLeftArea,
           let _ = screen.auxiliaryTopRightArea {
            hasNotch = true
        } else {
            hasNotch = false
        }

        let size: NSSize
        if expanded {
            let contentHeight: CGFloat = expandedMaxHeight
            size = NSSize(width: expandedWidth, height: contentHeight)
        } else {
            size = collapsedSize
        }

        let x = screenFrame.midX - size.width / 2
        let menuBarHeight: CGFloat = screenFrame.maxY - screen.visibleFrame.maxY
        let y: CGFloat
        if hasNotch {
            // Position flush with top of screen, overlapping the notch area
            y = screenFrame.maxY - size.height
        } else {
            // Position just below menu bar
            y = screenFrame.maxY - menuBarHeight - size.height - 4
        }

        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }

    private func scheduleAutoDismiss() {
        autoDismissTask?.cancel()
        autoDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            if !state.isExpanded && !state.items.contains(where: { $0.status == .waitingForInput }) {
                hide()
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

    func windowWillClose(_ notification: Notification) {
        panel = nil
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }
}
