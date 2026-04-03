//
//  ShellSession.swift
//  Liney
//
//  Author: everettjf
//

import AppKit
import Combine
import Darwin
import Foundation

func lineyAugmentedExecutablePath(
    _ existingPath: String?,
    homeDirectory: String = NSHomeDirectory()
) -> String {
    let userDirectories = [
        ".local/bin",
        ".cargo/bin",
        ".bun/bin",
        ".deno/bin",
    ].map {
        URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent($0, isDirectory: true)
            .path
    }

    let preferredDirectories = userDirectories + [
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "/usr/local/bin",
        "/usr/local/sbin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]
    let existingDirectories = existingPath?
        .split(separator: ":")
        .map(String.init) ?? []

    var seen = Set<String>()
    var orderedDirectories: [String] = []

    for directory in preferredDirectories + existingDirectories {
        let trimmed = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        if seen.insert(trimmed).inserted {
            orderedDirectories.append(trimmed)
        }
    }

    return orderedDirectories.joined(separator: ":")
}

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
    private let processReaper: @Sendable (TerminalLaunchConfiguration) -> Void
    private var launchConfiguration: TerminalLaunchConfiguration
    private var isFocusedInWorkspace = false

    init(snapshot: PaneSnapshot) {
        let launchConfiguration = Self.makeLaunchConfiguration(
            backendConfiguration: snapshot.backendConfiguration,
            preferredWorkingDirectory: snapshot.preferredWorkingDirectory
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
        self.processReaper = LineyTerminalManagedProcessReaper.reap
        configureSurfaceCallbacks()
    }

    init(
        snapshot: PaneSnapshot,
        surfaceController: ManagedTerminalSessionSurfaceController,
        processReaper: @escaping @Sendable (TerminalLaunchConfiguration) -> Void = LineyTerminalManagedProcessReaper.reap
    ) {
        self.id = snapshot.id
        self.requestedEngine = snapshot.preferredEngine
        self.backendConfiguration = snapshot.backendConfiguration
        self.resolvedEngine = snapshot.preferredEngine
        self.preferredWorkingDirectory = snapshot.preferredWorkingDirectory
        self.launchConfiguration = Self.makeLaunchConfiguration(
            backendConfiguration: snapshot.backendConfiguration,
            preferredWorkingDirectory: snapshot.preferredWorkingDirectory
        )
        self.title = launchConfiguration.command.displayName
        self.surfaceController = surfaceController
        self.processReaper = processReaper
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
        launchConfiguration = Self.makeLaunchConfiguration(
            backendConfiguration: backendConfiguration,
            preferredWorkingDirectory: preferredWorkingDirectory
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

        let previousLaunchConfiguration = launchConfiguration
        launchConfiguration = Self.makeLaunchConfiguration(
            backendConfiguration: backendConfiguration,
            preferredWorkingDirectory: preferredWorkingDirectory
        )
        surfaceController.updateLaunchConfiguration(launchConfiguration)
        processReaper(previousLaunchConfiguration)
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
        let currentLaunchConfiguration = launchConfiguration
        surfaceController.terminateManagedSession()
        processReaper(currentLaunchConfiguration)
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
        surfaceController.sendText(command)
        surfaceController.sendReturn()
    }

    func snapshot() -> PaneSnapshot {
        PaneSnapshot(
            id: id,
            preferredWorkingDirectory: preferredWorkingDirectory,
            preferredEngine: requestedEngine,
            backendConfiguration: restorableBackendConfiguration()
        )
    }

    func isUsing(pathPrefix: String) -> Bool {
        let candidates = [effectiveWorkingDirectory, preferredWorkingDirectory]
        return candidates.contains { $0 == pathPrefix || $0.hasPrefix(pathPrefix + "/") }
    }

    private static func defaultEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = lineyAugmentedExecutablePath(environment["PATH"])
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["TERM_PROGRAM"] = "Liney"
        environment["TERM_PROGRAM_VERSION"] = currentVersion()
        environment["LANG"] = environment["LANG"] ?? "en_US.UTF-8"

        // When launched from Finder/Dock, SSH_AUTH_SOCK may not be inherited.
        // Fall back to querying launchctl so git/ssh can use the system agent.
        if environment["SSH_AUTH_SOCK"] == nil {
            if let sock = Self.launchctlGetenv("SSH_AUTH_SOCK") {
                environment["SSH_AUTH_SOCK"] = sock
            }
        }

        return environment
    }

    private static func launchctlGetenv(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["getenv", name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == true ? nil : value
        } catch {
            return nil
        }
    }

    private static func currentVersion() -> String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return shortVersion?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "0.0.0"
    }

    private static func makeLaunchConfiguration(
        backendConfiguration: SessionBackendConfiguration,
        preferredWorkingDirectory: String
    ) -> TerminalLaunchConfiguration {
        let baseEnvironment = LineyTerminalManagedProcessReaper.prepareEnvironment(defaultEnvironment())
        return backendConfiguration.makeLaunchConfiguration(
            preferredWorkingDirectory: preferredWorkingDirectory,
            baseEnvironment: baseEnvironment
        )
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

    private func restorableBackendConfiguration() -> SessionBackendConfiguration {
        guard isLikelyTmuxSession else {
            return backendConfiguration
        }

        switch backendConfiguration.kind {
        case .localShell:
            var configuration = backendConfiguration.localShellConfiguration
            configuration.shellArguments = ["-lc", "tmux attach || tmux"]
            return SessionBackendConfiguration(
                kind: .localShell,
                localShell: configuration,
                ssh: nil,
                agent: nil
            )

        case .ssh:
            guard var configuration = backendConfiguration.ssh else {
                return backendConfiguration
            }
            if configuration.remoteCommand?.localizedCaseInsensitiveContains("tmux") != true {
                configuration.remoteCommand = "tmux attach || tmux"
            }
            return .ssh(configuration)

        case .agent:
            return backendConfiguration
        }
    }

    private var isLikelyTmuxSession: Bool {
        let candidates = [
            title,
            launchConfiguration.command.displayName,
            launchConfiguration.command.arguments.joined(separator: " "),
            backendConfiguration.ssh?.remoteCommand ?? "",
            backendConfiguration.localShell?.shellArguments.joined(separator: " ") ?? "",
        ]
        return candidates.contains { $0.localizedCaseInsensitiveContains("tmux") }
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

nonisolated struct LineyTerminalManagedProcessMetadata: Equatable {
    var shellPID: Int32?
    var loginPID: Int32?
    var tty: String?

    init(shellPID: Int32? = nil, loginPID: Int32? = nil, tty: String? = nil) {
        self.shellPID = shellPID
        self.loginPID = loginPID
        self.tty = tty
    }

    init(contents: String) {
        var shellPID: Int32?
        var loginPID: Int32?
        var tty: String?

        for line in contents.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }

            switch parts[0] {
            case "shell_pid":
                shellPID = Int32(parts[1])
            case "login_pid":
                loginPID = Int32(parts[1])
            case "tty":
                tty = parts[1].isEmpty ? nil : parts[1]
            default:
                continue
            }
        }

        self.init(shellPID: shellPID, loginPID: loginPID, tty: tty)
    }
}

nonisolated struct LineyTerminalManagedProcessControl {
    var processGroupID: @Sendable (Int32) -> Int32
    var sendSignal: @Sendable (Int32, Int32) -> Int32

    static let live = LineyTerminalManagedProcessControl(
        processGroupID: { Darwin.getpgid($0) },
        sendSignal: { Darwin.kill($0, $1) }
    )
}

nonisolated enum LineyTerminalManagedProcessReaper {
    static let sessionIDEnvironmentKey = "LINEY_SESSION_ID"
    static let metadataPathEnvironmentKey = "LINEY_SESSION_METADATA_PATH"

    static func prepareEnvironment(
        _ environment: [String: String],
        fileManager: FileManager = .default
    ) -> [String: String] {
        var environment = environment
        let sessionID = UUID().uuidString.lowercased()
        let metadataDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("liney-terminal-sessions", isDirectory: true)
        try? fileManager.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)

        let metadataPath = metadataDirectory
            .appendingPathComponent("\(sessionID).env", isDirectory: false)
            .path
        if fileManager.fileExists(atPath: metadataPath) {
            try? fileManager.removeItem(atPath: metadataPath)
        }

        environment[sessionIDEnvironmentKey] = sessionID
        environment[metadataPathEnvironmentKey] = metadataPath
        return environment
    }

    static func reap(_ launchConfiguration: TerminalLaunchConfiguration) {
        reap(launchConfiguration, fileManager: .default, processControl: .live)
    }

    static func reap(
        _ launchConfiguration: TerminalLaunchConfiguration,
        fileManager: FileManager,
        processControl: LineyTerminalManagedProcessControl
    ) {
        guard let metadataPath = launchConfiguration.environment[metadataPathEnvironmentKey],
              !metadataPath.isEmpty else { return }

        let metadata = readMetadata(atPath: metadataPath, fileManager: fileManager)
        if fileManager.fileExists(atPath: metadataPath) {
            try? fileManager.removeItem(atPath: metadataPath)
        }

        guard let metadata else { return }
        terminateProcesses(for: metadata, processControl: processControl)
    }

    private static func readMetadata(
        atPath path: String,
        fileManager: FileManager
    ) -> LineyTerminalManagedProcessMetadata? {
        guard fileManager.fileExists(atPath: path),
              let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }

        let metadata = LineyTerminalManagedProcessMetadata(contents: contents)
        if metadata.shellPID == nil && metadata.loginPID == nil {
            return nil
        }
        return metadata
    }

    private static func terminateProcesses(
        for metadata: LineyTerminalManagedProcessMetadata,
        processControl: LineyTerminalManagedProcessControl
    ) {
        if let shellPID = metadata.shellPID, shellPID > 1 {
            let processGroupID = processControl.processGroupID(shellPID)
            if processGroupID > 1 {
                _ = processControl.sendSignal(-processGroupID, SIGTERM)
            }
            _ = processControl.sendSignal(shellPID, SIGTERM)
        }

        if let loginPID = metadata.loginPID, loginPID > 1 {
            _ = processControl.sendSignal(loginPID, SIGTERM)
        }
    }
}
