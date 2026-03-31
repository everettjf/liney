//
//  TerminalSurface.swift
//  Liney
//
//  Author: everettjf
//

import AppKit
import Foundation

struct TerminalViewportStatus: Equatable {
    var total: UInt64
    var offset: UInt64
    var length: UInt64

    var progress: Double? {
        let maxOffset = max(Int64(total) - Int64(length), 0)
        guard maxOffset > 0 else { return nil }
        return Double(offset) / Double(maxOffset)
    }
}

struct TerminalSurfaceStatusSnapshot: Equatable {
    var rendererHealthy = true
    var searchQuery: String?
    var searchTotal: Int?
    var searchSelected: Int?
    var isReadOnly = false
    var viewport: TerminalViewportStatus?
}

@MainActor
protocol TerminalSurfaceController: AnyObject {
    var resolvedEngine: TerminalEngineKind { get }
    var view: NSView { get }
    var onResize: ((Int, Int) -> Void)? { get set }
    var onTitleChange: ((String) -> Void)? { get set }
    var onWorkingDirectoryChange: ((String?) -> Void)? { get set }
    var onFocus: (() -> Void)? { get set }
    var onStatusChange: ((TerminalSurfaceStatusSnapshot) -> Void)? { get set }
    func sendText(_ text: String)
    func sendReturn()
    func focus()
    func setFocused(_ isFocused: Bool)
    func beginSearch(initialText: String?)
    func updateSearch(_ text: String)
    func searchNext()
    func searchPrevious()
    func endSearch()
    func toggleReadOnly()
}

@MainActor
protocol ManagedTerminalSessionSurfaceController: TerminalSurfaceController {
    var managedPID: Int32? { get }
    var isManagedSessionRunning: Bool { get }
    var needsConfirmQuit: Bool { get }
    var onProcessExit: ((Int32?) -> Void)? { get set }
    func updateLaunchConfiguration(_ configuration: TerminalLaunchConfiguration)
    func startManagedSessionIfNeeded()
    func restartManagedSession()
    func terminateManagedSession()
}

enum TerminalSurfaceFactory {
    @MainActor
    static func make(
        preferred _: TerminalEngineKind,
        launchConfiguration: TerminalLaunchConfiguration
    ) -> ManagedTerminalSessionSurfaceController {
        if lineyIsRunningTests() {
            return LineyTestManagedTerminalSurfaceController(launchConfiguration: launchConfiguration)
        }
        return LineyGhosttyController(launchConfiguration: launchConfiguration)
    }
}

@MainActor
private final class LineyTestManagedTerminalSurfaceController: ManagedTerminalSessionSurfaceController {
    let resolvedEngine: TerminalEngineKind = .libghosttyPreferred
    let view = NSView(frame: .zero)

    var onResize: ((Int, Int) -> Void)?
    var onTitleChange: ((String) -> Void)?
    var onWorkingDirectoryChange: ((String?) -> Void)?
    var onFocus: (() -> Void)?
    var onStatusChange: ((TerminalSurfaceStatusSnapshot) -> Void)?
    var onProcessExit: ((Int32?) -> Void)?

    var managedPID: Int32?
    var isManagedSessionRunning = false
    var needsConfirmQuit = false

    private var launchConfiguration: TerminalLaunchConfiguration

    init(launchConfiguration: TerminalLaunchConfiguration) {
        self.launchConfiguration = launchConfiguration
    }

    func sendText(_ text: String) {}

    func sendReturn() {}

    func focus() {
        onFocus?()
    }

    func setFocused(_ isFocused: Bool) {}

    func beginSearch(initialText: String?) {}

    func updateSearch(_ text: String) {}

    func searchNext() {}

    func searchPrevious() {}

    func endSearch() {}

    func toggleReadOnly() {}

    func updateLaunchConfiguration(_ configuration: TerminalLaunchConfiguration) {
        launchConfiguration = configuration
    }

    func startManagedSessionIfNeeded() {
        guard !isManagedSessionRunning else { return }
        isManagedSessionRunning = true
        managedPID = 1
        onWorkingDirectoryChange?(launchConfiguration.workingDirectory)
        onTitleChange?(launchConfiguration.command.displayName)
        onStatusChange?(TerminalSurfaceStatusSnapshot())
    }

    func restartManagedSession() {
        isManagedSessionRunning = true
        managedPID = 1
        onWorkingDirectoryChange?(launchConfiguration.workingDirectory)
        onTitleChange?(launchConfiguration.command.displayName)
        onStatusChange?(TerminalSurfaceStatusSnapshot())
    }

    func terminateManagedSession() {
        guard isManagedSessionRunning else { return }
        isManagedSessionRunning = false
        managedPID = nil
        onProcessExit?(nil)
    }
}

func lineyTextFinderAction(for sender: Any?) -> NSTextFinder.Action? {
    guard let menuItem = sender as? NSMenuItem else { return nil }
    return NSTextFinder.Action(rawValue: menuItem.tag)
}

enum LineyGhosttySearchNavigation: String {
    case previous
    case next
}

func lineyGhosttySearchBindingAction(for query: String) -> String {
    "search:\(query)"
}

func lineyGhosttySearchNavigationBindingAction(_ direction: LineyGhosttySearchNavigation) -> String {
    "navigate_search:\(direction.rawValue)"
}

func lineyTerminalDropText(fileURLs: [URL], plainText: String?) -> String? {
    let quotedPaths = fileURLs
        .filter(\.isFileURL)
        .map(\.path)
        .filter { !$0.isEmpty }
        .map(\.shellQuoted)

    if !quotedPaths.isEmpty {
        return quotedPaths.joined(separator: " ")
    }

    guard let plainText, !plainText.isEmpty else { return nil }
    return plainText
}
