//
//  LineyGhosttyController.swift
//  Liney
//
//  Author: everettjf
//

import AppKit
import Carbon
import Foundation
import GhosttyKit
import UserNotifications

@MainActor
final class LineyGhosttyController: ManagedTerminalSessionSurfaceController {
    var resolvedEngine: TerminalEngineKind { .libghosttyPreferred }
    var view: NSView { terminalView }
    var onResize: ((Int, Int) -> Void)?
    var onTitleChange: ((String) -> Void)?
    var onWorkingDirectoryChange: ((String?) -> Void)?
    var onFocus: (() -> Void)?
    var onStatusChange: ((TerminalSurfaceStatusSnapshot) -> Void)?
    var onProcessExit: ((Int32?) -> Void)?
    var onWorkspaceAction: ((TerminalWorkspaceAction) -> Void)?

    var managedPID: Int32? { nil }
    var isManagedSessionRunning: Bool {
        guard let surface = terminalView.surface else { return false }
        return !ghostty_surface_process_exited(surface)
    }
    var needsConfirmQuit: Bool {
        guard let surface = terminalView.surface else { return false }
        return ghostty_surface_needs_confirm_quit(surface)
    }

    var currentSurface: ghostty_surface_t? { terminalView.surface }

    private let terminalView: LineyGhosttySurfaceView
    private var launchConfiguration: TerminalLaunchConfiguration
    private var latestTitle: String

    init(launchConfiguration: TerminalLaunchConfiguration) {
        self.launchConfiguration = launchConfiguration
        self.latestTitle = launchConfiguration.command.displayName
        self.terminalView = LineyGhosttySurfaceView()
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        terminalView.controller = self
    }

    func sendText(_ text: String) {
        terminalView.insertTerminalText(text)
    }

    func sendReturn() {
        terminalView.insertTerminalReturn()
    }

    func beginSearch(initialText: String?) {
        if let initialText, !initialText.isEmpty {
            _ = terminalView.performBindingAction(lineyGhosttySearchBindingAction(for: initialText))
            return
        }

        _ = terminalView.performBindingAction("start_search")
    }

    func updateSearch(_ text: String) {
        _ = terminalView.performBindingAction(lineyGhosttySearchBindingAction(for: text))
    }

    func searchNext() {
        _ = terminalView.performBindingAction(lineyGhosttySearchNavigationBindingAction(.next))
    }

    func searchPrevious() {
        _ = terminalView.performBindingAction(lineyGhosttySearchNavigationBindingAction(.previous))
    }

    func endSearch() {
        _ = terminalView.performBindingAction("end_search")
    }

    func selectedText() -> String? {
        terminalView.currentSelectionText()
    }

    func toggleReadOnly() {
        focus()
        _ = terminalView.performBindingAction("toggle_readonly")
    }

    func focus() {
        terminalView.window?.makeFirstResponder(terminalView)
    }

    func setFocused(_ isFocused: Bool) {
        terminalView.setWorkspaceFocus(isFocused)
    }

    func updateLaunchConfiguration(_ configuration: TerminalLaunchConfiguration) {
        launchConfiguration = configuration
    }

    func applyConfig(_ config: ghostty_config_t) {
        guard let surface = currentSurface else { return }
        ghostty_surface_update_config(surface, config)
        terminalView.syncSurfaceMetrics()
    }

    func startManagedSessionIfNeeded() {
        let wasNew = terminalView.surface == nil
        terminalView.ensureSurface(runtime: LineyGhosttyRuntime.shared, launchConfiguration: launchConfiguration)
        terminalView.syncSurfaceMetrics()
        if wasNew, terminalView.surface != nil, terminalView.window != nil {
            terminalView.resurfaceAfterLazyStart()
        }
    }

    func restartManagedSession() {
        terminalView.recreateSurface(runtime: LineyGhosttyRuntime.shared, launchConfiguration: launchConfiguration)
        terminalView.syncSurfaceMetrics()
    }

    func terminateManagedSession() {
        LineyGhosttySecureInputManager.shared.release(controller: self)
        terminalView.destroySurface()
    }

    func handleGhosttyAction(_ action: ghostty_action_s, on surface: ghostty_surface_t) -> Bool {
        switch action.tag {
        case GHOSTTY_ACTION_NEW_SPLIT:
            if let appDelegate = NSApp.delegate as? AppDelegate,
               !appDelegate.shouldDispatchGhosttySplitAction(action.action.new_split) {
                return true
            }
            dispatchWorkspaceAction(workspaceAction(for: action.action.new_split))
            return true

        case GHOSTTY_ACTION_GOTO_SPLIT:
            guard let navigationAction = workspaceNavigationAction(for: action.action.goto_split) else {
                return false
            }
            dispatchWorkspaceAction(navigationAction)
            return true

        case GHOSTTY_ACTION_RESIZE_SPLIT:
            guard let direction = paneFocusDirection(for: action.action.resize_split.direction) else {
                return false
            }
            dispatchWorkspaceAction(.resizeFocusedSplit(direction, amount: action.action.resize_split.amount))
            return true

        case GHOSTTY_ACTION_EQUALIZE_SPLITS:
            dispatchWorkspaceAction(.equalizeSplits)
            return true

        case GHOSTTY_ACTION_TOGGLE_SPLIT_ZOOM:
            dispatchWorkspaceAction(.togglePaneZoom)
            return true

        case GHOSTTY_ACTION_CLOSE_WINDOW:
            dispatchWorkspaceAction(.closePane)
            return true

        case GHOSTTY_ACTION_SET_TITLE, GHOSTTY_ACTION_SET_TAB_TITLE:
            if let title = action.action.set_title.title.map(String.init(cString:)), !title.isEmpty {
                latestTitle = title
                DispatchQueue.main.async { [weak self] in
                    self?.onTitleChange?(title)
                }
            }
            return true

        case GHOSTTY_ACTION_PWD:
            let workingDirectory = action.action.pwd.pwd.map(String.init(cString:))
            DispatchQueue.main.async { [weak self] in
                self?.onWorkingDirectoryChange?(workingDirectory)
            }
            return true

        case GHOSTTY_ACTION_CELL_SIZE:
            terminalView.syncSurfaceMetrics()
            return true

        case GHOSTTY_ACTION_RENDERER_HEALTH:
            terminalView.rendererHealthy = action.action.renderer_health == GHOSTTY_RENDERER_HEALTH_HEALTHY
            return true

        case GHOSTTY_ACTION_COMMAND_FINISHED:
            handleCommandFinished(action.action.command_finished)
            return true

        case GHOSTTY_ACTION_DESKTOP_NOTIFICATION:
            let title = action.action.desktop_notification.title.map(String.init(cString:)) ?? "Terminal"
            let body = action.action.desktop_notification.body.map(String.init(cString:))
            let islandEnabled = IslandPanelController.shared.workspaceStore?.appSettings.dynamicIslandEnabled == true
            if islandEnabled {
                onWorkspaceAction?(.desktopNotification(title: body ?? title))
            } else {
                LineyGhosttyNotificationCenter.shared.deliver(title: title, body: body)
            }
            return true

        case GHOSTTY_ACTION_RING_BELL:
            NSSound.beep()
            return true

        case GHOSTTY_ACTION_OPEN_URL:
            guard let cString = action.action.open_url.url,
                  let url = URL(string: String(cString: cString)) else {
                return false
            }
            NSWorkspace.shared.open(url)
            return true

        case GHOSTTY_ACTION_MOUSE_SHAPE:
            terminalView.setCursorShape(action.action.mouse_shape)
            return true

        case GHOSTTY_ACTION_MOUSE_VISIBILITY:
            terminalView.setCursorVisibility(action.action.mouse_visibility == GHOSTTY_MOUSE_VISIBLE)
            return true

        case GHOSTTY_ACTION_MOUSE_OVER_LINK:
            terminalView.hoveredLink = action.action.mouse_over_link.url.map(String.init(cString:))
            return true

        case GHOSTTY_ACTION_SCROLLBAR:
            terminalView.scrollbarState = LineyGhosttyScrollbarState(action.action.scrollbar)
            return true

        case GHOSTTY_ACTION_READONLY:
            terminalView.isReadOnly = action.action.readonly == GHOSTTY_READONLY_ON
            return true

        case GHOSTTY_ACTION_SECURE_INPUT:
            LineyGhosttySecureInputManager.shared.apply(action.action.secure_input, controller: self)
            return true

        case GHOSTTY_ACTION_COPY_TITLE_TO_CLIPBOARD:
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(latestTitle, forType: .string)
            return true

        case GHOSTTY_ACTION_START_SEARCH:
            terminalView.searchNeedle = action.action.start_search.needle.map(String.init(cString:)) ?? ""
            return true

        case GHOSTTY_ACTION_END_SEARCH:
            terminalView.searchNeedle = nil
            return true

        case GHOSTTY_ACTION_SEARCH_TOTAL:
            terminalView.searchTotal = Int(action.action.search_total.total)
            return true

        case GHOSTTY_ACTION_SEARCH_SELECTED:
            terminalView.searchSelected = Int(action.action.search_selected.selected)
            return true

        case GHOSTTY_ACTION_KEY_SEQUENCE:
            terminalView.updateKeySequence(action.action.key_sequence)
            return true

        case GHOSTTY_ACTION_KEY_TABLE:
            terminalView.updateKeyTable(action.action.key_table)
            return true

        case GHOSTTY_ACTION_COLOR_CHANGE:
            terminalView.applyColorChange(action.action.color_change)
            return true

        default:
            return false
        }
    }

    func handleManagedProcessExit(exitCode: Int32?) {
        DispatchQueue.main.async { [weak self] in
            self?.onProcessExit?(exitCode)
        }
    }

    func handleSurfaceClose(processAlive: Bool) {
        guard lineyGhosttyShouldReportProcessExitForSurfaceClose(processAlive: processAlive) else { return }
        handleManagedProcessExit(exitCode: nil)
    }

    func handleCommandFinished(_ action: ghostty_action_command_finished_s) {
        // Ghostty reports shell command completion separately from shell process
        // exit. Treating this as a process exit causes normal commands such as
        // `clear` to close panes or tabs unexpectedly.
        _ = lineyGhosttyShouldReportProcessExitForCommandFinished(action)
    }

    func completeClipboardRequest(_ text: String, state: UnsafeMutableRawPointer?, confirmed: Bool) {
        guard let surface = currentSurface else { return }
        text.withCString { pointer in
            ghostty_surface_complete_clipboard_request(surface, pointer, state, confirmed)
        }
    }

    func confirmClipboardRead(
        text: String,
        state: UnsafeMutableRawPointer?,
        request: ghostty_clipboard_request_e
    ) {
        let alert = NSAlert()
        switch request {
        case GHOSTTY_CLIPBOARD_REQUEST_PASTE:
            alert.messageText = "Paste clipboard into terminal?"
            alert.informativeText = "Pasting into a shell can execute commands. Review the clipboard contents before continuing."
        case GHOSTTY_CLIPBOARD_REQUEST_OSC_52_READ:
            alert.messageText = "Allow terminal to read the clipboard?"
            alert.informativeText = "A running program requested clipboard access through OSC 52."
        default:
            alert.messageText = "Allow clipboard access?"
            alert.informativeText = "A running program requested clipboard access."
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = ClipboardPreviewView(text: text)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            completeClipboardRequest(text, state: state, confirmed: true)
        } else {
            completeClipboardRequest("", state: state, confirmed: false)
        }
    }

    func confirmClipboardWrite(text: String, location: ghostty_clipboard_e) {
        confirmClipboardWrite(
            items: [LineyGhosttyClipboardPayload(mimeType: "text/plain;charset=utf-8", text: text)],
            location: location
        )
    }

    func confirmClipboardWrite(items: [LineyGhosttyClipboardPayload], location: ghostty_clipboard_e) {
        let alert = NSAlert()
        alert.messageText = "Allow terminal to update the clipboard?"
        alert.informativeText = location == GHOSTTY_CLIPBOARD_SELECTION
            ? "A running program wants to write to the selection clipboard."
            : "A running program wants to write to the system clipboard."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Cancel")
        let previewText = items.first(where: \.isPlainText)?.text ?? items.first?.text ?? ""
        alert.accessoryView = ClipboardPreviewView(text: previewText)

        guard alert.runModal() == .alertFirstButtonReturn,
              let pasteboard = lineyGhosttyPasteboard(for: location) else {
            return
        }

        lineyGhosttyWriteClipboard(items, to: pasteboard)
    }

    fileprivate func handleSurfaceResize(cols: Int, rows: Int) {
        DispatchQueue.main.async { [weak self] in
            self?.onResize?(cols, rows)
        }
    }

    private func workspaceAction(for direction: ghostty_action_split_direction_e) -> TerminalWorkspaceAction {
        switch direction {
        case GHOSTTY_SPLIT_DIRECTION_LEFT:
            return .createSplit(axis: .vertical, placement: .before)
        case GHOSTTY_SPLIT_DIRECTION_UP:
            return .createSplit(axis: .horizontal, placement: .before)
        case GHOSTTY_SPLIT_DIRECTION_DOWN:
            return .createSplit(axis: .horizontal, placement: .after)
        default:
            return .createSplit(axis: .vertical, placement: .after)
        }
    }

    private func workspaceNavigationAction(for navigation: ghostty_action_goto_split_e) -> TerminalWorkspaceAction? {
        switch navigation {
        case GHOSTTY_GOTO_SPLIT_PREVIOUS:
            return .focusPreviousPane
        case GHOSTTY_GOTO_SPLIT_NEXT:
            return .focusNextPane
        case GHOSTTY_GOTO_SPLIT_UP:
            return .focusPane(.up)
        case GHOSTTY_GOTO_SPLIT_LEFT:
            return .focusPane(.left)
        case GHOSTTY_GOTO_SPLIT_DOWN:
            return .focusPane(.down)
        case GHOSTTY_GOTO_SPLIT_RIGHT:
            return .focusPane(.right)
        default:
            return nil
        }
    }

    private func paneFocusDirection(for direction: ghostty_action_resize_split_direction_e) -> PaneFocusDirection? {
        switch direction {
        case GHOSTTY_RESIZE_SPLIT_UP:
            return .up
        case GHOSTTY_RESIZE_SPLIT_DOWN:
            return .down
        case GHOSTTY_RESIZE_SPLIT_LEFT:
            return .left
        case GHOSTTY_RESIZE_SPLIT_RIGHT:
            return .right
        default:
            return nil
        }
    }

    private func dispatchWorkspaceAction(_ action: TerminalWorkspaceAction) {
        // Defer layout/session mutations until after libghostty finishes processing the current callback.
        DispatchQueue.main.async { [weak self] in
            self?.onWorkspaceAction?(action)
        }
    }

    fileprivate func notifyStatusChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onStatusChange?(terminalView.statusSnapshot)
        }
    }
}

func lineyGhosttyShouldReportProcessExitForSurfaceClose(processAlive: Bool) -> Bool {
    !processAlive
}

func lineyGhosttyShouldReportProcessExitForCommandFinished(
    _: ghostty_action_command_finished_s
) -> Bool {
    false
}

func lineyGhosttyShouldRefreshSurface(
    after previous: LineyGhosttySurfaceMetricsSignature?,
    next: LineyGhosttySurfaceMetricsSignature
) -> Bool {
    previous != next
}

private struct LineyGhosttyScrollbarState {
    let total: UInt64
    let offset: UInt64
    let length: UInt64

    init(_ source: ghostty_action_scrollbar_s) {
        total = source.total
        offset = source.offset
        length = source.len
    }
}

struct LineyGhosttySurfaceMetricsSignature: Equatable {
    let width: Int
    let height: Int
    let scale: Double
    let displayID: CGDirectDisplayID?
}

@MainActor
private final class LineyGhosttySurfaceView: NSView {
    weak var controller: LineyGhosttyController?

    var surface: ghostty_surface_t?
    var rendererHealthy = true {
        didSet { controller?.notifyStatusChange() }
    }
    var hoveredLink: String?
    var scrollbarState: LineyGhosttyScrollbarState? {
        didSet { controller?.notifyStatusChange() }
    }
    var searchNeedle: String? {
        didSet { controller?.notifyStatusChange() }
    }
    var searchTotal: Int? {
        didSet { controller?.notifyStatusChange() }
    }
    var searchSelected: Int? {
        didSet { controller?.notifyStatusChange() }
    }
    var isReadOnly = false {
        didSet { controller?.notifyStatusChange() }
    }

    private var trackingAreaToken: NSTrackingArea?
    private var windowObservers: [NSObjectProtocol] = []
    private var surfaceUserdataToken: UnsafeMutableRawPointer?
    private var pointerShape: ghostty_action_mouse_shape_e = GHOSTTY_MOUSE_SHAPE_DEFAULT
    private var cursorVisible = true
    private var cursorHiddenToken = false
    private var mouseInside = false
    private var markedText = NSMutableAttributedString()
    private var keyTextAccumulator: [String]?
    private var activeKeySequence: [String] = []
    private var activeKeyTables: [String] = []
    private var surfaceBackgroundColor: NSColor?
    private var workspaceFocused = false
    private var backendConfiguration: SessionBackendConfiguration = .local()
    private var handledTextInputCommand = false
    private var lastPerformKeyEvent: TimeInterval?
    private var markedSelectionRange = NSRange(location: NSNotFound, length: 0)
    private var currentTextInputEventKeyCode: UInt16?
    private var currentTextInputHadMarkedText = false
    private var lastMetricsSignature: LineyGhosttySurfaceMetricsSignature?
    private let imeDebugLogger = LineyGhosttyIMEDebugLogger.shared

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        registerForDraggedTypes([.fileURL, .URL, .string])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func insertText(_ insertString: Any) {
        insertText(insertString, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    func ensureSurface(runtime: LineyGhosttyRuntime, launchConfiguration: TerminalLaunchConfiguration) {
        guard surface == nil else { return }
        createSurface(runtime: runtime, launchConfiguration: launchConfiguration)
    }

    func recreateSurface(runtime: LineyGhosttyRuntime, launchConfiguration: TerminalLaunchConfiguration) {
        destroySurface()
        createSurface(runtime: runtime, launchConfiguration: launchConfiguration)
    }

    func resurfaceAfterLazyStart() {
        guard let parent = superview else { return }
        let constraints = parent.constraints.filter { ($0.firstItem as? NSView) === self || ($0.secondItem as? NSView) === self }
        removeFromSuperview()
        parent.addSubview(self)
        NSLayoutConstraint.activate(constraints)
    }

    func setWorkspaceFocus(_ isFocused: Bool) {
        workspaceFocused = isFocused
        guard let surface else { return }
        ghostty_surface_set_focus(surface, isFocused)
    }

    func destroySurface() {
        guard let surface else { return }
        self.surface = nil
        if let surfaceUserdataToken {
            LineyGhosttyControllerRegistry.shared.unregister(surfaceUserdataToken)
            self.surfaceUserdataToken = nil
        }
        ghostty_surface_set_focus(surface, false)
        ghostty_surface_free(surface)
        layer = nil
        mouseInside = false
        rendererHealthy = true
        scrollbarState = nil
        searchNeedle = nil
        searchTotal = nil
        searchSelected = nil
        isReadOnly = false
        lastMetricsSignature = nil
        updateCursorVisibility()
    }

    var statusSnapshot: TerminalSurfaceStatusSnapshot {
        TerminalSurfaceStatusSnapshot(
            rendererHealthy: rendererHealthy,
            searchQuery: searchNeedle,
            searchTotal: searchTotal,
            searchSelected: searchSelected,
            isReadOnly: isReadOnly,
            viewport: scrollbarState.map {
                TerminalViewportStatus(total: $0.total, offset: $0.offset, length: $0.length)
            }
        )
    }

    override func updateTrackingAreas() {
        if let trackingAreaToken {
            removeTrackingArea(trackingAreaToken)
        }
        let trackingAreaToken = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingAreaToken)
        self.trackingAreaToken = trackingAreaToken
        super.updateTrackingAreas()
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result, let surface {
            ghostty_surface_set_focus(surface, true)
            controller?.onFocus?()
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result, let surface {
            ghostty_surface_set_focus(surface, false)
        }
        return result
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateWindowObservers()
        syncSurfaceMetrics()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        syncSurfaceMetrics()
    }

    override func layout() {
        super.layout()
        syncSurfaceMetrics()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncSurfaceMetrics()
    }

    override func setBoundsSize(_ newSize: NSSize) {
        super.setBoundsSize(newSize)
        syncSurfaceMetrics()
    }

    override func updateLayer() {
        super.updateLayer()
        syncSurfaceMetrics()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        syncSurfaceMetrics()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard cursorVisible else {
            addCursorRect(bounds, cursor: .arrow)
            return
        }
        addCursorRect(bounds, cursor: cursor(for: pointerShape))
    }

    override func cursorUpdate(with event: NSEvent) {
        super.cursorUpdate(with: event)
        applyCursor()
    }

    override func mouseEntered(with event: NSEvent) {
        mouseInside = true
        updateCursorVisibility()
        applyCursor()
        sendMousePosition(event)
    }

    override func mouseExited(with event: NSEvent) {
        mouseInside = false
        hoveredLink = nil
        updateCursorVisibility()
        NSCursor.arrow.set()
    }

    func syncSurfaceMetrics() {
        guard let surface else { return }

        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        ghostty_surface_set_content_scale(surface, scale, scale)

        // Keep the Core Animation layer's contentsScale in sync so that
        // CA correctly interprets the Metal-rendered texture's pixel density.
        // Without this, moving from Retina (2x) to a 1x display causes CA
        // to double-scale the already-correct 1x render output.
        if let layer = self.layer {
            layer.contentsScale = scale
        }

        let backingBounds = convertToBacking(bounds)
        let width = max(Int(backingBounds.width.rounded()), 1)
        let height = max(Int(backingBounds.height.rounded()), 1)
        ghostty_surface_set_size(
            surface,
            UInt32(width),
            UInt32(height)
        )

        let displayID = window?.screen?.displayID
        if let displayID {
            ghostty_surface_set_display_id(surface, displayID)
        }

        let nextSignature = LineyGhosttySurfaceMetricsSignature(
            width: width,
            height: height,
            scale: scale,
            displayID: displayID
        )
        if lineyGhosttyShouldRefreshSurface(after: lastMetricsSignature, next: nextSignature) {
            ghostty_surface_refresh(surface)
        }
        lastMetricsSignature = nextSignature

        let size = ghostty_surface_size(surface)
        controller?.handleSurfaceResize(cols: Int(size.columns), rows: Int(size.rows))
    }

    func setCursorShape(_ shape: ghostty_action_mouse_shape_e) {
        pointerShape = shape
        invalidateCursorRectsForCurrentWindow()
        applyCursor()
    }

    func setCursorVisibility(_ visible: Bool) {
        cursorVisible = visible
        updateCursorVisibility()
        invalidateCursorRectsForCurrentWindow()
        applyCursor()
    }

    func updateKeySequence(_ sequence: ghostty_action_key_sequence_s) {
        if sequence.active {
            activeKeySequence = ["sequence"]
        } else {
            activeKeySequence.removeAll()
        }
    }

    func updateKeyTable(_ keyTable: ghostty_action_key_table_s) {
        switch keyTable.tag {
        case GHOSTTY_KEY_TABLE_ACTIVATE:
            if let name = keyTable.value.activate.name.map(String.init(cString:)),
               !activeKeyTables.contains(name) {
                activeKeyTables.append(name)
            }
        case GHOSTTY_KEY_TABLE_DEACTIVATE:
            if let name = keyTable.value.activate.name.map(String.init(cString:)) {
                activeKeyTables.removeAll(where: { $0 == name })
            }
        case GHOSTTY_KEY_TABLE_DEACTIVATE_ALL:
            activeKeyTables.removeAll()
        default:
            break
        }
    }

    func applyColorChange(_ change: ghostty_action_color_change_s) {
        guard change.kind == GHOSTTY_ACTION_COLOR_KIND_BACKGROUND else { return }
        wantsLayer = true
        let color = NSColor(
            red: CGFloat(change.r) / 255,
            green: CGFloat(change.g) / 255,
            blue: CGFloat(change.b) / 255,
            alpha: 1
        )
        surfaceBackgroundColor = color
        layer?.backgroundColor = color.cgColor
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let surface else { return }
        let mods = ghosttyMods(event.modifierFlags)
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, mods)
    }

    override func mouseUp(with event: NSEvent) {
        guard let surface else { return }
        let mods = ghosttyMods(event.modifierFlags)
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, mods)
        ghostty_surface_mouse_pressure(surface, 0, 0)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let surface else { return }
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, ghosttyMods(event.modifierFlags))
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let surface else { return }
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, ghosttyMods(event.modifierFlags))
    }

    override func otherMouseDown(with event: NSEvent) {
        guard let surface else { return }
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, mouseButton(for: event.buttonNumber), ghosttyMods(event.modifierFlags))
    }

    override func otherMouseUp(with event: NSEvent) {
        guard let surface else { return }
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, mouseButton(for: event.buttonNumber), ghosttyMods(event.modifierFlags))
    }

    override func mouseMoved(with event: NSEvent) {
        sendMousePosition(event)
        applyCursor()
    }

    override func mouseDragged(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        var scrollX = event.scrollingDeltaX
        var scrollY = event.scrollingDeltaY
        if event.hasPreciseScrollingDeltas {
            scrollX *= 2
            scrollY *= 2
        }
        ghostty_surface_mouse_scroll(surface, scrollX, scrollY, scrollMods(for: event))
    }

    private func scrollMods(for event: NSEvent) -> ghostty_input_scroll_mods_t {
        var value: Int32 = 0
        if event.hasPreciseScrollingDeltas {
            value |= 0b0000_0001
        }
        let momentum: Int32
        switch event.momentumPhase {
        case .began:      momentum = 1
        case .stationary: momentum = 2
        case .changed:    momentum = 3
        case .ended:      momentum = 4
        case .cancelled:  momentum = 5
        case .mayBegin:   momentum = 6
        default:          momentum = 0
        }
        value |= (momentum << 1)
        return ghostty_input_scroll_mods_t(value)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggedText(from: sender.draggingPasteboard) == nil ? [] : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        draggedText(from: sender.draggingPasteboard) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let text = draggedText(from: sender.draggingPasteboard) else { return false }
        window?.makeFirstResponder(self)
        insertTerminalText(text)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard let surface else {
            super.keyDown(with: event)
            return
        }

        logArrowKeyDebug(event, phase: "keyDown")

        if let appDelegate = NSApp.delegate as? AppDelegate,
           appDelegate.performShortcutAction(matching: event) {
            return
        }

        if lineyGhosttyOptionDeleteEscapeSequence(keyCode: event.keyCode, modifierFlags: event.modifierFlags) != nil {
            logArrowKeyDebug(event, phase: "keyDown option-delete")
            sendOptionDelete(keyCode: event.keyCode, on: surface)
            return
        }

        if let escapeSequence = lineyGhosttySSHWordNavigationEscapeSequence(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags,
            backendConfiguration: backendConfiguration
        ) {
            logArrowKeyDebug(event, phase: "keyDown ssh-word-nav")
            sendSSHWordNavigation(escapeSequence)
            return
        }

        let (translationEvent, translationMods) = translationState(for: event, on: surface)

        if shouldPreferRawKeyEvent(for: event) {
            logArrowKeyDebug(event, phase: "keyDown raw-preferred")
            sendRawKeyEvent(
                event,
                on: surface,
                translationEvent: translationEvent,
                translationMods: translationMods
            )
            return
        }

        let textModifiers = event.modifierFlags.intersection([.command, .control])
        if textModifiers.isEmpty {
            let hadMarkedTextBeforeInterpretation = hasMarkedText()
            keyTextAccumulator = []
            handledTextInputCommand = false
            currentTextInputEventKeyCode = event.keyCode
            currentTextInputHadMarkedText = hadMarkedTextBeforeInterpretation
            defer {
                currentTextInputEventKeyCode = nil
                currentTextInputHadMarkedText = false
            }
            interpretKeyEvents([translationEvent])
            let accumulated = keyTextAccumulator?.joined() ?? ""
            keyTextAccumulator = nil
            let hasMarkedTextAfterInterpretation = hasMarkedText()

            if LineyGhosttyTextInputRouting.shouldSyncPreeditAfterTextInterpretation(
                hadMarkedTextBeforeInterpretation: hadMarkedTextBeforeInterpretation,
                hasMarkedTextAfterInterpretation: hasMarkedTextAfterInterpretation
            ) {
                syncPreedit()
            }

            if !accumulated.isEmpty {
                logIMEDebug("keyDown translated text=\(accumulated.debugDescription)")
                sendTranslatedKeyEvent(
                    event,
                    on: surface,
                    translationEvent: translationEvent,
                    translationMods: translationMods,
                    text: accumulated
                )
                return
            }

            if handledTextInputCommand {
                logIMEDebug("keyDown handled by text input command")
                return
            }

            if !LineyGhosttyTextInputRouting.shouldDispatchRawKeyFallbackAfterTextInterpretation(
                accumulatedText: accumulated,
                handledTextInputCommand: handledTextInputCommand,
                hadMarkedTextBeforeInterpretation: hadMarkedTextBeforeInterpretation,
                hasMarkedTextAfterInterpretation: hasMarkedTextAfterInterpretation
            ) {
                logIMEDebug("keyDown IME consumed event, skip raw fallback")
                return
            }

            let composing = LineyGhosttyTextInputRouting.shouldMarkRawKeyEventAsComposing(
                hadMarkedTextBeforeInterpretation: hadMarkedTextBeforeInterpretation,
                hasMarkedTextAfterInterpretation: hasMarkedTextAfterInterpretation
            )
            logIMEDebug("keyDown raw fallback composing=\(composing)")
            sendRawKeyEvent(
                event,
                on: surface,
                translationEvent: translationEvent,
                translationMods: translationMods,
                composing: composing
            )
            return
        }

        sendRawKeyEvent(
            event,
            on: surface,
            translationEvent: translationEvent,
            translationMods: translationMods
        )
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        guard let firstResponder = window?.firstResponder as? NSView,
              firstResponder === self || firstResponder.isDescendant(of: self) else {
            return false
        }
        guard let surface else { return false }

        if lineyGhosttyOptionDeleteEscapeSequence(keyCode: event.keyCode, modifierFlags: event.modifierFlags) != nil {
            sendOptionDelete(keyCode: event.keyCode, on: surface)
            return true
        }

        if let escapeSequence = lineyGhosttySSHWordNavigationEscapeSequence(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags,
            backendConfiguration: backendConfiguration
        ) {
            sendSSHWordNavigation(escapeSequence)
            return true
        }

        if shouldPreferRawKeyEvent(for: event) {
            keyDown(with: event)
            return true
        }

        if hasMarkedText(),
           !event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) {
            return false
        }

        let flags = bindingFlags(for: event, on: surface)
        if lineyGhosttyShouldAttemptMenuKeyEquivalent(
            bindingFlags: flags,
            modifierFlags: event.modifierFlags,
            hasActiveKeySequence: !activeKeySequence.isEmpty,
            hasActiveKeyTable: !activeKeyTables.isEmpty
        ),
           let menu = NSApp.mainMenu,
           menu.performKeyEquivalent(with: event) {
            return true
        }

        if let appDelegate = NSApp.delegate as? AppDelegate,
           appDelegate.performShortcutAction(matching: event) {
            return true
        }

        if flags != nil {
            keyDown(with: event)
            return true
        }

        let resolution = resolveGhosttyEquivalentKey(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            characters: event.characters,
            modifierFlags: event.modifierFlags,
            eventTimestamp: event.timestamp,
            lastPerformKeyEvent: lastPerformKeyEvent
        )
        lastPerformKeyEvent = resolution.nextLastPerformKeyEvent

        guard let equivalent = resolution.equivalent,
              let finalEvent = NSEvent.keyEvent(
                with: .keyDown,
                location: event.locationInWindow,
                modifierFlags: event.modifierFlags,
                timestamp: event.timestamp,
                windowNumber: event.windowNumber,
                context: nil,
                characters: equivalent,
                charactersIgnoringModifiers: equivalent,
                isARepeat: event.isARepeat,
                keyCode: event.keyCode
              ) else {
            return false
        }

        keyDown(with: finalEvent)
        return true
    }

    override func keyUp(with event: NSEvent) {
        guard let surface else {
            super.keyUp(with: event)
            return
        }
        let keyEvent = event.ghosttyKeyEvent(GHOSTTY_ACTION_RELEASE)
        _ = ghostty_surface_key(surface, keyEvent)
    }

    override func flagsChanged(with event: NSEvent) {
        guard let surface else {
            super.flagsChanged(with: event)
            return
        }

        guard let action = lineyGhosttyModifierAction(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags
        ) else {
            return
        }
        let keyEvent = event.ghosttyKeyEvent(action)
        _ = ghostty_surface_key(surface, keyEvent)
    }

    override func doCommand(by selector: Selector) {
        logIMEDebug("doCommand selector=\(NSStringFromSelector(selector)) marked=\(hasMarkedText()) text=\(markedText.string.debugDescription)")
        if let lastPerformKeyEvent,
           let currentEvent = NSApp.currentEvent,
           lastPerformKeyEvent == currentEvent.timestamp {
            NSApp.sendEvent(currentEvent)
            return
        }

        switch LineyGhosttyTextInputCommandAction.resolve(selector: selector, hasMarkedText: hasMarkedText()) {
        case .scrollToTop:
            handledTextInputCommand = true
            _ = performBindingAction("scroll_to_top")
        case .scrollToBottom:
            handledTextInputCommand = true
            _ = performBindingAction("scroll_to_bottom")
        case .moveBackwardWord:
            guard backendConfiguration.kind == .ssh else { break }
            handledTextInputCommand = true
            sendSSHWordNavigation("\u{1B}b")
        case .moveForwardWord:
            guard backendConfiguration.kind == .ssh else { break }
            handledTextInputCommand = true
            sendSSHWordNavigation("\u{1B}f")
        case .deleteWordBackward:
            handledTextInputCommand = true
            if hasMarkedText() {
                unmarkText()
            }
            if let surface {
                sendOptionDelete(keyCode: UInt16(kVK_Delete), on: surface)
            }
        case .deleteWordForward:
            handledTextInputCommand = true
            if hasMarkedText() {
                unmarkText()
            }
            if let surface {
                sendOptionDelete(keyCode: UInt16(kVK_ForwardDelete), on: surface)
            }
        case .deleteBackwardInMarkedText:
            handledTextInputCommand = true
            deleteBackwardInMarkedText()
        case .cancelMarkedText:
            handledTextInputCommand = true
            unmarkText()
        case .none:
            break
        }
    }

    @IBAction func copy(_ sender: Any?) {
        _ = performBindingAction("copy_to_clipboard")
    }

    @IBAction func paste(_ sender: Any?) {
        _ = performBindingAction("paste_from_clipboard")
    }

    @IBAction override func selectAll(_ sender: Any?) {
        _ = performBindingAction("select_all")
    }

    @IBAction func find(_ sender: Any?) {
        if let selected = currentSelectionText(), !selected.isEmpty {
            _ = performBindingAction(lineyGhosttySearchBindingAction(for: selected))
        } else {
            _ = performBindingAction("start_search")
        }
    }

    @IBAction func findNext(_ sender: Any?) {
        _ = performBindingAction(lineyGhosttySearchNavigationBindingAction(.next))
    }

    @IBAction func findPrevious(_ sender: Any?) {
        _ = performBindingAction(lineyGhosttySearchNavigationBindingAction(.previous))
    }

    @IBAction func findHide(_ sender: Any?) {
        _ = performBindingAction("end_search")
    }

    @IBAction override func performTextFinderAction(_ sender: Any?) {
        guard let action = lineyTextFinderAction(for: sender) else {
            super.performTextFinderAction(sender)
            return
        }

        switch action {
        case .showFindInterface:
            find(sender)
        case .nextMatch:
            findNext(sender)
        case .previousMatch:
            findPrevious(sender)
        case .hideFindInterface:
            findHide(sender)
        default:
            super.performTextFinderAction(sender)
        }
    }

    @IBAction func toggleReadonly(_ sender: Any?) {
        _ = performBindingAction("toggle_readonly")
    }

    override func validRequestor(
        forSendType sendType: NSPasteboard.PasteboardType?,
        returnType: NSPasteboard.PasteboardType?
    ) -> Any? {
        let supported: [NSPasteboard.PasteboardType] = [.string, NSPasteboard.PasteboardType("public.utf8-plain-text")]

        if (returnType == nil || supported.contains(returnType!)) &&
            (sendType == nil || supported.contains(sendType!)) {
            if let sendType, supported.contains(sendType),
               let surface,
               !ghostty_surface_has_selection(surface) {
                return super.validRequestor(forSendType: sendType, returnType: returnType)
            }
            return self
        }

        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(findHide(_:)):
            return searchNeedle != nil
        case #selector(toggleReadonly(_:)):
            menuItem.state = isReadOnly ? .on : .off
            return true
        default:
            return true
        }
    }

    func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        guard let selection = currentSelectionText() else { return false }
        pboard.clearContents()
        pboard.declareTypes([.string], owner: nil)
        pboard.setString(selection, forType: .string)
        return true
    }

    func readSelection(from pboard: NSPasteboard) -> Bool {
        guard let string = pboard.lineyGhosttyBestString else { return false }
        sendText(string)
        return true
    }

    private func createSurface(runtime: LineyGhosttyRuntime, launchConfiguration: TerminalLaunchConfiguration) {
        guard let controller else { return }
        backendConfiguration = launchConfiguration.backendConfiguration

        let surfaceUserdataToken = LineyGhosttyControllerRegistry.shared.register(controller)
        let surface = withSurfaceConfig(
            userdata: surfaceUserdataToken,
            launchConfiguration: launchConfiguration
        ) { configuration in
            ghostty_surface_new(runtime.app, &configuration)
        }

        guard let surface else {
            LineyGhosttyControllerRegistry.shared.unregister(surfaceUserdataToken)
            return
        }
        self.surface = surface
        self.surfaceUserdataToken = surfaceUserdataToken
        if let surfaceBackgroundColor {
            wantsLayer = true
            layer?.backgroundColor = surfaceBackgroundColor.cgColor
        }
        ghostty_surface_set_focus(surface, workspaceFocused)
        syncSurfaceMetrics()
    }

    private func withSurfaceConfig<T>(
        userdata: UnsafeMutableRawPointer,
        launchConfiguration: TerminalLaunchConfiguration,
        body: (inout ghostty_surface_config_s) -> T
    ) -> T {
        var configuration = ghostty_surface_config_new()
        configuration.platform_tag = GHOSTTY_PLATFORM_MACOS
        configuration.platform = ghostty_platform_u(
            macos: ghostty_platform_macos_s(nsview: Unmanaged.passUnretained(self).toOpaque())
        )
        configuration.userdata = userdata
        configuration.scale_factor = Double(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        configuration.context = GHOSTTY_SURFACE_CONTEXT_SPLIT
        configuration.wait_after_command = false

        let workingDirectory = strdup(launchConfiguration.workingDirectory)
        let command = strdup(launchConfiguration.ghosttyCommand)
        let initialInput = launchConfiguration.initialInput.flatMap { strdup($0) }
        defer {
            free(workingDirectory)
            free(command)
            free(initialInput)
        }

        configuration.working_directory = workingDirectory.map { UnsafePointer($0) }
        configuration.command = command.map { UnsafePointer($0) }
        configuration.initial_input = initialInput.map { UnsafePointer($0) }

        let envStorage = launchConfiguration.environment
            .sorted { $0.key < $1.key }
            .map { (strdup($0.key), strdup($0.value)) }
        defer {
            for (key, value) in envStorage {
                free(key)
                free(value)
            }
        }

        if envStorage.isEmpty {
            configuration.env_vars = nil
            configuration.env_var_count = 0
            return body(&configuration)
        }

        var envVars = envStorage.map {
            ghostty_env_var_s(
                key: $0.0.map { UnsafePointer($0) },
                value: $0.1.map { UnsafePointer($0) }
            )
        }
        return envVars.withUnsafeMutableBufferPointer { buffer in
            configuration.env_vars = buffer.baseAddress
            configuration.env_var_count = buffer.count
            return body(&configuration)
        }
    }

    private func sendMousePosition(_ event: NSEvent) {
        guard let surface else { return }
        let position = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, position.x, frame.height - position.y, ghosttyMods(event.modifierFlags))
    }

    private func sendRawKeyEvent(
        _ event: NSEvent,
        on surface: ghostty_surface_t,
        translationEvent: NSEvent? = nil,
        translationMods: NSEvent.ModifierFlags? = nil,
        composing: Bool = false
    ) {
        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        let resolvedEvent: NSEvent
        let resolvedMods: NSEvent.ModifierFlags
        if let translationEvent, let translationMods {
            resolvedEvent = translationEvent
            resolvedMods = translationMods
        } else {
            resolvedEvent = event
            resolvedMods = event.modifierFlags
        }

        var keyEvent = resolvedEvent.ghosttyKeyEvent(
            action,
            translationMods: resolvedMods,
            composing: composing
        )
        if let text = textForGhosttyKeyEvent(resolvedEvent), shouldSendGhosttyText(text) {
            text.withCString { textPointer in
                keyEvent.text = textPointer
                _ = ghostty_surface_key(surface, keyEvent)
            }
        } else {
            keyEvent.consumed_mods = GHOSTTY_MODS_NONE
            _ = ghostty_surface_key(surface, keyEvent)
        }
    }

    private func sendTranslatedKeyEvent(
        _ event: NSEvent,
        on surface: ghostty_surface_t,
        translationEvent: NSEvent,
        translationMods: NSEvent.ModifierFlags,
        text: String,
        composing: Bool = false
    ) {
        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        var keyEvent = translationEvent.ghosttyKeyEvent(
            action,
            translationMods: translationMods,
            composing: composing
        )
        if shouldSendGhosttyText(text) {
            text.withCString { textPointer in
                keyEvent.text = textPointer
                _ = ghostty_surface_key(surface, keyEvent)
            }
        } else {
            keyEvent.consumed_mods = GHOSTTY_MODS_NONE
            _ = ghostty_surface_key(surface, keyEvent)
        }
    }

    func performBindingAction(_ action: String) -> Bool {
        guard let surface else { return false }
        return ghostty_surface_binding_action(surface, action, UInt(action.lengthOfBytes(using: .utf8)))
    }

    private func bindingFlags(for event: NSEvent, on surface: ghostty_surface_t) -> ghostty_binding_flags_e? {
        var keyEvent = event.ghosttyKeyEvent(GHOSTTY_ACTION_PRESS, translationMods: event.modifierFlags)
        let text = textForGhosttyKeyEvent(event).flatMap { shouldSendGhosttyText($0) ? $0 : nil } ?? ""
        var flags = ghostty_binding_flags_e(0)
        let isBinding = text.withCString { pointer in
            keyEvent.text = pointer
            return ghostty_surface_key_is_binding(surface, keyEvent, &flags)
        }
        return isBinding ? flags : nil
    }

    private func sendText(_ string: String) {
        guard let surface else { return }
        let utf8Count = string.utf8.count
        guard utf8Count > 0 else { return }
        string.withCString { pointer in
            ghostty_surface_text(surface, pointer, UInt(utf8Count))
        }
    }

    private func sendSSHWordNavigation(_ sequence: String) {
        guard let surface else { return }

        switch sequence {
        case "\u{1B}b":
            sendSSHMetaLetter("b", keyCode: UInt16(kVK_ANSI_B), on: surface)
        case "\u{1B}f":
            sendSSHMetaLetter("f", keyCode: UInt16(kVK_ANSI_F), on: surface)
        default:
            sendText(sequence)
        }
    }

    private func sendOptionDelete(keyCode: UInt16, on surface: ghostty_surface_t) {
        var press = ghostty_input_key_s()
        press.action = GHOSTTY_ACTION_PRESS
        press.mods = GHOSTTY_MODS_ALT
        press.consumed_mods = GHOSTTY_MODS_NONE
        press.keycode = UInt32(keyCode)
        press.text = nil
        press.unshifted_codepoint = keyCode == UInt16(kVK_Delete) ? 0x7F : 0
        press.composing = false
        _ = ghostty_surface_key(surface, press)

        var release = ghostty_input_key_s()
        release.action = GHOSTTY_ACTION_RELEASE
        release.mods = GHOSTTY_MODS_ALT
        release.consumed_mods = GHOSTTY_MODS_NONE
        release.keycode = UInt32(keyCode)
        release.text = nil
        release.unshifted_codepoint = keyCode == UInt16(kVK_Delete) ? 0x7F : 0
        release.composing = false
        _ = ghostty_surface_key(surface, release)
    }

    private func sendSSHMetaLetter(_ character: Character, keyCode: UInt16, on surface: ghostty_surface_t) {
        guard let scalar = character.unicodeScalars.first else { return }

        var press = ghostty_input_key_s()
        press.action = GHOSTTY_ACTION_PRESS
        press.mods = GHOSTTY_MODS_ALT
        press.consumed_mods = GHOSTTY_MODS_NONE
        press.keycode = UInt32(keyCode)
        press.text = nil
        press.unshifted_codepoint = scalar.value
        press.composing = false
        _ = ghostty_surface_key(surface, press)

        var release = ghostty_input_key_s()
        release.action = GHOSTTY_ACTION_RELEASE
        release.mods = GHOSTTY_MODS_ALT
        release.consumed_mods = GHOSTTY_MODS_NONE
        release.keycode = UInt32(keyCode)
        release.text = nil
        release.unshifted_codepoint = scalar.value
        release.composing = false
        _ = ghostty_surface_key(surface, release)
    }

    private func shouldPreferRawKeyEvent(for event: NSEvent) -> Bool {
        LineyGhosttyTextInputRouting.shouldPreferRawKeyEvent(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags
        )
    }

    private func translationState(
        for event: NSEvent,
        on surface: ghostty_surface_t
    ) -> (NSEvent, NSEvent.ModifierFlags) {
        let translatedMods = appKitMods(
            ghostty_surface_key_translation_mods(surface, ghosttyMods(event.modifierFlags)),
            fallback: event.modifierFlags
        )

        guard translatedMods != event.modifierFlags,
              let translatedEvent = NSEvent.keyEvent(
                with: event.type,
                location: event.locationInWindow,
                modifierFlags: translatedMods,
                timestamp: event.timestamp,
                windowNumber: event.windowNumber,
                context: nil,
                characters: event.characters(byApplyingModifiers: translatedMods) ?? "",
                charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                isARepeat: event.isARepeat,
                keyCode: event.keyCode
              ) else {
            return (event, translatedMods)
        }

        return (translatedEvent, translatedMods)
    }

    private func deleteBackwardInMarkedText() {
        guard markedText.length > 0 else { return }
        var state = LineyGhosttyMarkedTextState(text: markedText.string, selectedRange: markedSelectionRange)
        state.deleteBackward()
        markedText.mutableString.setString(state.text)
        markedSelectionRange = state.selectedRange
        syncPreedit()
    }

    func insertTerminalText(_ string: String) {
        sendText(string)
    }

    func insertTerminalReturn() {
        guard let surface else { return }

        var press = ghostty_input_key_s()
        press.action = GHOSTTY_ACTION_PRESS
        press.mods = GHOSTTY_MODS_NONE
        press.consumed_mods = GHOSTTY_MODS_NONE
        press.keycode = UInt32(kVK_Return)
        press.text = nil
        press.unshifted_codepoint = 0x0D
        press.composing = false
        _ = ghostty_surface_key(surface, press)

        var release = ghostty_input_key_s()
        release.action = GHOSTTY_ACTION_RELEASE
        release.mods = GHOSTTY_MODS_NONE
        release.consumed_mods = GHOSTTY_MODS_NONE
        release.keycode = UInt32(kVK_Return)
        release.text = nil
        release.unshifted_codepoint = 0x0D
        release.composing = false
        _ = ghostty_surface_key(surface, release)
    }

    private func syncPreedit() {
        guard let surface else { return }
        let string = markedText.string
        if string.isEmpty {
            "".withCString { pointer in
                ghostty_surface_preedit(surface, pointer, 0)
            }
            return
        }

        string.withCString { pointer in
            ghostty_surface_preedit(surface, pointer, UInt(string.utf8.count))
        }
    }

    func currentSelectionText() -> String? {
        guard let surface else { return nil }
        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }
        return String(cString: text.text)
    }

    private func applyCursor() {
        guard mouseInside else { return }
        if cursorVisible {
            cursor(for: pointerShape).set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func updateCursorVisibility() {
        let shouldHide = mouseInside && !cursorVisible
        guard shouldHide != cursorHiddenToken else { return }
        cursorHiddenToken = shouldHide
        if shouldHide {
            NSCursor.hide()
        } else {
            NSCursor.unhide()
        }
    }

    private func cursor(for shape: ghostty_action_mouse_shape_e) -> NSCursor {
        switch shape {
        case GHOSTTY_MOUSE_SHAPE_DEFAULT:
            return .arrow
        case GHOSTTY_MOUSE_SHAPE_TEXT, GHOSTTY_MOUSE_SHAPE_VERTICAL_TEXT:
            return .iBeam
        case GHOSTTY_MOUSE_SHAPE_GRAB:
            return .openHand
        case GHOSTTY_MOUSE_SHAPE_GRABBING:
            return .closedHand
        case GHOSTTY_MOUSE_SHAPE_POINTER:
            return .pointingHand
        case GHOSTTY_MOUSE_SHAPE_CONTEXT_MENU:
            return .contextualMenu
        case GHOSTTY_MOUSE_SHAPE_CROSSHAIR:
            return .crosshair
        case GHOSTTY_MOUSE_SHAPE_NOT_ALLOWED:
            return .operationNotAllowed
        case GHOSTTY_MOUSE_SHAPE_E_RESIZE,
             GHOSTTY_MOUSE_SHAPE_W_RESIZE,
             GHOSTTY_MOUSE_SHAPE_EW_RESIZE:
            return .resizeLeftRight
        case GHOSTTY_MOUSE_SHAPE_N_RESIZE,
             GHOSTTY_MOUSE_SHAPE_S_RESIZE,
             GHOSTTY_MOUSE_SHAPE_NS_RESIZE:
            return .resizeUpDown
        default:
            return .arrow
        }
    }

    private func mouseButton(for buttonNumber: Int) -> ghostty_input_mouse_button_e {
        switch buttonNumber {
        case 2:
            return GHOSTTY_MOUSE_MIDDLE
        case 3:
            return GHOSTTY_MOUSE_FOUR
        case 4:
            return GHOSTTY_MOUSE_FIVE
        default:
            return GHOSTTY_MOUSE_UNKNOWN
        }
    }

    private func draggedText(from pasteboard: NSPasteboard) -> String? {
        let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        return lineyTerminalDropText(fileURLs: fileURLs, plainText: pasteboard.string(forType: .string))
    }

    private func invalidateCursorRectsForCurrentWindow() {
        window?.invalidateCursorRects(for: self)
    }

    private func updateWindowObservers() {
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers.removeAll()

        guard let window else { return }
        let notifications: [Notification.Name] = [
            NSWindow.didChangeScreenNotification,
            NSWindow.didChangeBackingPropertiesNotification,
            NSWindow.didResizeNotification
        ]

        for name in notifications {
            let observer = NotificationCenter.default.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.syncSurfaceMetrics()
                }
            }
            windowObservers.append(observer)
        }
    }

    deinit {
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

@MainActor
final class LineyGhosttyControllerRegistry {
    static let shared = LineyGhosttyControllerRegistry()

    private final class WeakBox {
        weak var controller: LineyGhosttyController?

        init(controller: LineyGhosttyController) {
            self.controller = controller
        }
    }

    private var controllers: [UInt: WeakBox] = [:]

    func register(_ controller: LineyGhosttyController) -> UnsafeMutableRawPointer {
        let token = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
        controllers[UInt(bitPattern: token)] = WeakBox(controller: controller)
        return token
    }

    func controller(for address: UInt?) -> LineyGhosttyController? {
        guard let address else { return nil }
        return controllers[address]?.controller
    }

    func liveControllers() -> [LineyGhosttyController] {
        controllers = controllers.filter { $0.value.controller != nil }
        return controllers.values.compactMap(\.controller)
    }

    func unregister(_ token: UnsafeMutableRawPointer) {
        controllers.removeValue(forKey: UInt(bitPattern: token))
        token.deallocate()
    }
}

extension LineyGhosttySurfaceView: @preconcurrency NSServicesMenuRequestor {}

extension LineyGhosttySurfaceView: NSMenuItemValidation {}

extension LineyGhosttySurfaceView: @preconcurrency NSTextInputClient {
    func hasMarkedText() -> Bool {
        markedText.length > 0
    }

    func markedRange() -> NSRange {
        guard markedText.length > 0 else { return NSRange(location: NSNotFound, length: 0) }
        return NSRange(location: 0, length: markedText.length)
    }

    func selectedRange() -> NSRange {
        guard markedText.length > 0 else {
            return NSRange(location: NSNotFound, length: 0)
        }
        return LineyGhosttyMarkedTextState.clamp(markedSelectionRange, textLength: markedText.length)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let replacementText: String
        switch string {
        case let value as NSAttributedString:
            replacementText = value.string
        case let value as String:
            replacementText = value
        default:
            return
        }

        var state = LineyGhosttyMarkedTextState(text: markedText.string, selectedRange: markedSelectionRange)
        state.setMarkedText(
            replacementText,
            selectedRange: selectedRange,
            replacementRange: replacementRange
        )
        markedText = NSMutableAttributedString(string: state.text)
        markedSelectionRange = state.selectedRange
        logIMEDebug(
            "setMarkedText replacement=\(replacementText.debugDescription) selected=\(NSStringFromRange(selectedRange)) replacementRange=\(NSStringFromRange(replacementRange)) result=\(state.text.debugDescription)"
        )

        if keyTextAccumulator == nil {
            syncPreedit()
        }
    }

    func unmarkText() {
        guard markedText.length > 0 else { return }
        logIMEDebug("unmarkText old=\(markedText.string.debugDescription)")
        markedText.mutableString.setString("")
        markedSelectionRange = NSRange(location: NSNotFound, length: 0)
        syncPreedit()
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard range.length > 0, let selection = currentSelectionText() else { return nil }
        actualRange?.pointee = NSRange(location: 0, length: selection.count)
        return NSAttributedString(string: selection)
    }

    func characterIndex(for point: NSPoint) -> Int {
        0
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let surface else {
            return NSRect(origin: frame.origin, size: .zero)
        }

        var x: Double = 0
        var y: Double = 0
        var width: Double = Double(ghostty_surface_size(surface).cell_width_px)
        var height: Double = Double(ghostty_surface_size(surface).cell_height_px)
        ghostty_surface_ime_point(surface, &x, &y, &width, &height)

        if range.length == 0 {
            width = 0
        }

        let viewRect = NSRect(
            x: x,
            y: frame.size.height - y,
            width: width,
            height: max(height, Double(ghostty_surface_size(surface).cell_height_px))
        )
        let windowRect = convert(viewRect, to: nil)
        guard let window else { return windowRect }
        return window.convertToScreen(windowRect)
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        var characters = ""
        switch string {
        case let value as NSAttributedString:
            characters = value.string
        case let value as String:
            characters = value
        default:
            return
        }
        logIMEDebug(
            "insertText text=\(characters.debugDescription) replacementRange=\(NSStringFromRange(replacementRange)) keyCode=\(String(describing: currentTextInputEventKeyCode)) hadMarked=\(currentTextInputHadMarkedText) accumulator=\(keyTextAccumulator != nil)"
        )

        if LineyGhosttyTextInputRouting.shouldTreatInsertedTextAsMarkedTextDuringDeletion(
            insertedText: characters,
            keyCode: currentTextInputEventKeyCode,
            hadMarkedTextBeforeDeletion: currentTextInputHadMarkedText
        ) {
            markedText = NSMutableAttributedString(string: characters)
            markedSelectionRange = NSRange(location: markedText.length, length: 0)
            syncPreedit()
            return
        }

        unmarkText()

        if var accumulator = keyTextAccumulator {
            accumulator.append(characters)
            keyTextAccumulator = accumulator
            return
        }

        sendText(characters)
    }

    private func logIMEDebug(_ message: String) {
        imeDebugLogger.log(message)
    }

    private func logArrowKeyDebug(_ event: NSEvent, phase: String) {
        switch event.keyCode {
        case UInt16(kVK_LeftArrow), UInt16(kVK_RightArrow), UInt16(kVK_UpArrow), UInt16(kVK_DownArrow):
            logIMEDebug(
                "\(phase) keyCode=\(event.keyCode) modifiers=\(event.modifierFlags.rawValue) chars=\(String(describing: event.characters)) charsIgnoring=\(String(describing: event.charactersIgnoringModifiers)) backend=\(backendConfiguration.kind)"
            )
        default:
            break
        }
    }
}

private final class LineyGhosttyIMEDebugLogger {
    static let shared = LineyGhosttyIMEDebugLogger(environment: ProcessInfo.processInfo.environment)

    private let enabled: Bool
    private let processID = ProcessInfo.processInfo.processIdentifier

    init(environment: [String: String]) {
        self.enabled = lineyGhosttyShouldEnableIMEDebugLogging(environment: environment)
    }

    func log(_ message: String) {
        guard enabled else { return }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[IME] \(timestamp) pid=\(processID) \(message)\n"
        print(line, terminator: "")
    }
}

private final class ClipboardPreviewView: NSScrollView {
    init(text: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 380, height: 160))

        let textView = NSTextView(frame: bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.string = text

        borderType = .bezelBorder
        hasVerticalScroller = true
        documentView = textView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private extension NSScreen {
    var displayID: UInt32 {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { UInt32(truncating: $0) } ?? 0
    }
}

@MainActor
private final class LineyGhosttyNotificationCenter {
    static let shared = LineyGhosttyNotificationCenter()

    private var hasRequestedAuthorization = false

    func deliver(title: String, body: String?) {
        let center = UNUserNotificationCenter.current()
        if !hasRequestedAuthorization {
            hasRequestedAuthorization = true
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }

        let content = UNMutableNotificationContent()
        content.title = title
        if let body, !body.isEmpty {
            content.body = body
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "com.liney.ghostty.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }
}

@MainActor
private final class LineyGhosttySecureInputManager {
    static let shared = LineyGhosttySecureInputManager()

    private var activeControllers: Set<ObjectIdentifier> = []

    func apply(_ action: ghostty_action_secure_input_e, controller: LineyGhosttyController) {
        let controllerID = ObjectIdentifier(controller)
        switch action {
        case GHOSTTY_SECURE_INPUT_ON:
            activate(controllerID)
        case GHOSTTY_SECURE_INPUT_OFF:
            deactivate(controllerID)
        case GHOSTTY_SECURE_INPUT_TOGGLE:
            if activeControllers.contains(controllerID) {
                deactivate(controllerID)
            } else {
                activate(controllerID)
            }
        default:
            break
        }
    }

    func release(controller: LineyGhosttyController) {
        deactivate(ObjectIdentifier(controller))
    }

    private func activate(_ controllerID: ObjectIdentifier) {
        let wasEmpty = activeControllers.isEmpty
        activeControllers.insert(controllerID)
        if wasEmpty {
            EnableSecureEventInput()
        }
    }

    private func deactivate(_ controllerID: ObjectIdentifier) {
        let removed = activeControllers.remove(controllerID) != nil
        guard removed, activeControllers.isEmpty else { return }
        DisableSecureEventInput()
    }
}
