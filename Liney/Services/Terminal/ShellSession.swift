//
//  ShellSession.swift
//  Liney
//
//  Author: everettjf
//

import AppKit
import Combine
import Foundation

enum ShellSessionLifecycle: Equatable {
    case idle
    case starting
    case running
    case exited

    var hasActiveProcess: Bool {
        switch self {
        case .starting, .running:
            return true
        case .idle, .exited:
            return false
        }
    }
}

@MainActor
final class ShellSession: ObservableObject, Identifiable {
    let id: UUID
    let requestedEngine: TerminalEngineKind
    let backendConfiguration: SessionBackendConfiguration

    @Published var resolvedEngine: TerminalEngineKind
    @Published var title: String
    @Published var preferredWorkingDirectory: String
    @Published var reportedWorkingDirectory: String?
    @Published private(set) var lifecycle: ShellSessionLifecycle = .idle
    @Published var exitCode: Int32?
    @Published var pid: Int32?
    @Published var rows: Int = 24
    @Published var cols: Int = 80
    @Published var surfaceStatus = TerminalSurfaceStatusSnapshot()

    var onWorkspaceAction: ((TerminalWorkspaceAction) -> Void)?
    var onFocus: (() -> Void)?

    private let surfaceController: ManagedTerminalSessionSurfaceController
    private var launchConfiguration: TerminalLaunchConfiguration
    private var isFocusedInWorkspace = false

    init(snapshot: PaneSnapshot) {
        let launchConfiguration = snapshot.backendConfiguration.makeLaunchConfiguration(
            preferredWorkingDirectory: snapshot.preferredWorkingDirectory,
            baseEnvironment: ShellSession.defaultEnvironment()
        )

        let surface = TerminalSurfaceFactory.make(
            preferred: snapshot.preferredEngine,
            launchConfiguration: launchConfiguration
        )
        self.id = snapshot.id
        self.requestedEngine = snapshot.preferredEngine
        self.backendConfiguration = snapshot.backendConfiguration
        self.resolvedEngine = snapshot.preferredEngine
        self.preferredWorkingDirectory = snapshot.preferredWorkingDirectory
        self.launchConfiguration = launchConfiguration
        self.title = launchConfiguration.command.displayName
        self.surfaceController = surface
        configureSurfaceCallbacks()
    }

    init(snapshot: PaneSnapshot, surfaceController: ManagedTerminalSessionSurfaceController) {
        self.id = snapshot.id
        self.requestedEngine = snapshot.preferredEngine
        self.backendConfiguration = snapshot.backendConfiguration
        self.resolvedEngine = snapshot.preferredEngine
        self.preferredWorkingDirectory = snapshot.preferredWorkingDirectory
        self.launchConfiguration = snapshot.backendConfiguration.makeLaunchConfiguration(
            preferredWorkingDirectory: snapshot.preferredWorkingDirectory,
            baseEnvironment: ShellSession.defaultEnvironment()
        )
        self.title = launchConfiguration.command.displayName
        self.surfaceController = surfaceController
        configureSurfaceCallbacks()
    }

    private func configureSurfaceCallbacks() {
        self.resolvedEngine = surfaceController.resolvedEngine

        surfaceController.onResize = { [weak self] cols, rows in
            guard let self else { return }
            self.cols = max(cols, 2)
            self.rows = max(rows, 2)
        }
        surfaceController.onTitleChange = { [weak self] title in
            guard let self, !title.isEmpty else { return }
            self.title = title
        }
        surfaceController.onWorkingDirectoryChange = { [weak self] directory in
            self?.reportedWorkingDirectory = directory
        }
        surfaceController.onFocus = { [weak self] in
            self?.onFocus?()
        }
        surfaceController.onStatusChange = { [weak self] status in
            self?.surfaceStatus = status
        }

        surfaceController.onProcessExit = { [weak self] exitCode in
            guard let self else { return }
            self.applyProcessExit(exitCode)
        }
        if let ghosttySurface = surfaceController as? LineyGhosttyController {
            ghosttySurface.onWorkspaceAction = { [weak self] action in
                self?.onWorkspaceAction?(action)
            }
        }
    }

    var nsView: NSView {
        surfaceController.view
    }

    var effectiveWorkingDirectory: String {
        reportedWorkingDirectory ?? preferredWorkingDirectory
    }

    var backendLabel: String {
        backendConfiguration.displayName
    }

    var launchPath: String {
        launchConfiguration.command.executablePath
    }

    var launchArguments: [String] {
        launchConfiguration.command.arguments
    }

    var hasActiveProcess: Bool {
        lifecycle.hasActiveProcess
    }

    var isRunning: Bool {
        hasActiveProcess && needsQuitConfirmation
    }

    var needsQuitConfirmation: Bool {
        surfaceController.needsConfirmQuit
    }

    func startIfNeeded() {
        guard lifecycle == .idle else { return }
        start()
    }

    func start() {
        launchConfiguration = backendConfiguration.makeLaunchConfiguration(
            preferredWorkingDirectory: preferredWorkingDirectory,
            baseEnvironment: Self.defaultEnvironment()
        )
        title = launchConfiguration.command.displayName

        exitCode = nil
        lifecycle = .starting
        surfaceController.updateLaunchConfiguration(launchConfiguration)
        surfaceController.startManagedSessionIfNeeded()
        surfaceController.setFocused(isFocusedInWorkspace)
        syncManagedProcessStateAfterLaunch()
    }

    func restart(in workingDirectory: String? = nil) {
        if let workingDirectory {
            preferredWorkingDirectory = workingDirectory
            reportedWorkingDirectory = nil
        }

        launchConfiguration = backendConfiguration.makeLaunchConfiguration(
            preferredWorkingDirectory: preferredWorkingDirectory,
            baseEnvironment: Self.defaultEnvironment()
        )
        surfaceController.updateLaunchConfiguration(launchConfiguration)
        exitCode = nil
        lifecycle = .starting
        surfaceController.restartManagedSession()
        surfaceController.setFocused(isFocusedInWorkspace)
        syncManagedProcessStateAfterLaunch()
    }

    func updatePreferredWorkingDirectory(_ path: String, restartIfRunning: Bool) {
        preferredWorkingDirectory = path
        reportedWorkingDirectory = nil
        if restartIfRunning && hasActiveProcess {
            restart(in: path)
        }
    }

    func terminate() {
        surfaceController.terminateManagedSession()
        lifecycle = .exited
        pid = nil
    }

    func focus() {
        surfaceController.focus()
    }

    func setFocused(_ isFocused: Bool) {
        isFocusedInWorkspace = isFocused
        surfaceController.setFocused(isFocused)
    }

    func clear() {
        sendShellCommand("clear")
    }

    func beginSearch() {
        surfaceController.beginSearch(initialText: surfaceStatus.searchQuery)
    }

    func updateSearch(_ text: String) {
        surfaceController.updateSearch(text)
    }

    func searchNext() {
        surfaceController.searchNext()
    }

    func searchPrevious() {
        surfaceController.searchPrevious()
    }

    func endSearch() {
        surfaceController.endSearch()
    }

    func toggleReadOnly() {
        surfaceController.toggleReadOnly()
    }

    func insertText(_ text: String) {
        surfaceController.sendText(text)
    }

    func sendShellCommand(_ command: String) {
        surfaceController.sendText(command + "\n")
    }

    func snapshot() -> PaneSnapshot {
        PaneSnapshot(
            id: id,
            preferredWorkingDirectory: preferredWorkingDirectory,
            preferredEngine: requestedEngine,
            backendConfiguration: backendConfiguration
        )
    }

    func isUsing(pathPrefix: String) -> Bool {
        let candidates = [effectiveWorkingDirectory, preferredWorkingDirectory]
        return candidates.contains { $0 == pathPrefix || $0.hasPrefix(pathPrefix + "/") }
    }

    private static func defaultEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["TERM_PROGRAM"] = "Liney"
        environment["TERM_PROGRAM_VERSION"] = currentVersion()
        environment["LANG"] = environment["LANG"] ?? "en_US.UTF-8"
        return environment
    }

    private static func currentVersion() -> String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return shortVersion?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "0.0.0"
    }

    private func syncManagedProcessStateAfterLaunch() {
        pid = surfaceController.managedPID
        lifecycle = (surfaceController.isManagedSessionRunning || pid != nil) ? .running : .starting
    }

    private func applyProcessExit(_ exitCode: Int32?) {
        self.exitCode = exitCode
        lifecycle = .exited
        pid = nil
    }
}

enum TerminalWorkspaceAction {
    case createSplit(axis: PaneSplitAxis, placement: PaneSplitPlacement)
    case focusPane(PaneFocusDirection)
    case focusNextPane
    case focusPreviousPane
    case resizeFocusedSplit(PaneFocusDirection, amount: UInt16)
    case equalizeSplits
    case togglePaneZoom
    case closePane
}
