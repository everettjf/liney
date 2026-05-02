//
//  HookRunner.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

/// Fires user-defined lifecycle hooks. Spawns each command via `/bin/sh -c`,
/// passes context as environment variables, and logs every invocation
/// (timing, exit code, errors) to `~/.liney/hook.log`. Hooks are gated on
/// `AppSettings.hooksEnabled` (off by default) — when disabled,
/// `fire(_:context:)` is a no-op even if the file exists.
///
/// Per-command `sync` flag in hooks.json controls whether the caller blocks
/// until the command completes (true) or returns immediately and the command
/// runs on a background queue (false, default).
///
/// nonisolated for the same reason as HookSettingsPersistence — accessed
/// from background queues; default MainActor isolation would corrupt deinit.
nonisolated final class HookRunner: @unchecked Sendable {
    static let shared = HookRunner()

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.liney.hook-runner", qos: .utility)
    private let persistence: HookSettingsPersistence
    private let logger: HookLogger
    private var cachedSettings: HookSettings?
    private var cachedModificationDate: Date?
    private var masterEnabled: Bool = false

    /// Maximum total wall-clock time allowed when running app.on_quit hooks
    /// synchronously, so user mistakes don't hang quit.
    static let appQuitTimeout: TimeInterval = 2.0

    init(
        persistence: HookSettingsPersistence = HookSettingsPersistence(),
        logger: HookLogger = .shared
    ) {
        self.persistence = persistence
        self.logger = logger
    }

    /// Mirror the master switch from AppSettings. Cheap enough to call on every
    /// settings change.
    func updateMasterSwitch(_ enabled: Bool) {
        lock.lock()
        masterEnabled = enabled
        lock.unlock()
    }

    var isMasterEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return masterEnabled
    }

    /// Drop the cached parse so the next fire reads from disk again. Used after
    /// the user edits hooks.json.
    func invalidateCache() {
        lock.lock()
        cachedSettings = nil
        cachedModificationDate = nil
        lock.unlock()
    }

    /// Fire a hook. Sync commands block the caller; async commands are
    /// dispatched and run in the background. Use this for everything except
    /// `app.on_quit`, which has a special bounded-blocking path.
    func fire(_ kind: HookKind, context: HookContext) {
        guard let commands = preparedCommands(for: kind) else { return }
        guard !commands.isEmpty else { return }

        let env = context.environmentVariables(for: kind)
        let name = kind.rawValue
        let stateDirectory = persistence.stateDirectoryURL

        let syncCommands = commands.filter { $0.sync }
        let asyncCommands = commands.filter { !$0.sync }

        // Sync commands run inline so the caller waits for completion. The
        // caller chose to block by setting "sync": true.
        for command in syncCommands {
            runOne(command, kind: name, mode: "sync", environment: env, stateDirectory: stateDirectory)
        }

        // Async commands run on the runner's serial queue.
        guard !asyncCommands.isEmpty else { return }
        let logger = self.logger
        queue.async {
            for command in asyncCommands {
                Self.runOne(
                    command,
                    kind: name,
                    mode: "async",
                    environment: env,
                    stateDirectory: stateDirectory,
                    logger: logger
                )
            }
        }
    }

    /// Fire a hook and block (with `timeout` total) for completion. Used for
    /// `app.on_quit` so user cleanup gets a chance to run before exit. All
    /// commands run synchronously regardless of their `sync` flag — async
    /// commands started here would orphan when the app exits anyway.
    func fireBlocking(_ kind: HookKind, context: HookContext, timeout: TimeInterval) {
        guard let commands = preparedCommands(for: kind) else { return }
        guard !commands.isEmpty else { return }

        let env = context.environmentVariables(for: kind)
        let name = kind.rawValue
        let stateDirectory = persistence.stateDirectoryURL
        let deadline = Date().addingTimeInterval(timeout)
        for command in commands {
            let remaining = max(0.05, deadline.timeIntervalSinceNow)
            let perCommandTimeout = min(remaining, command.effectiveTimeout)
            runOne(
                command,
                kind: name,
                mode: "blocking",
                environment: env,
                stateDirectory: stateDirectory,
                timeoutOverride: perCommandTimeout
            )
            if Date() >= deadline {
                logger.log("hook \(name): aborted remaining commands (total budget exceeded)")
                break
            }
        }
    }

    private func runOne(
        _ command: HookCommand,
        kind: String,
        mode: String,
        environment: [String: String],
        stateDirectory: URL,
        timeoutOverride: TimeInterval? = nil
    ) {
        Self.runOne(
            command,
            kind: kind,
            mode: mode,
            environment: environment,
            stateDirectory: stateDirectory,
            logger: logger,
            timeoutOverride: timeoutOverride
        )
    }

    private static func runOne(
        _ command: HookCommand,
        kind: String,
        mode: String,
        environment: [String: String],
        stateDirectory: URL,
        logger: HookLogger,
        timeoutOverride: TimeInterval? = nil
    ) {
        guard let source = command.resolvedSource(stateDirectory: stateDirectory) else {
            logger.log("hook \(kind) [\(mode)]: skipped — no command or script set")
            return
        }
        let timeout = timeoutOverride ?? command.effectiveTimeout
        let result = Self.runProcess(
            source: source,
            hookName: kind,
            mode: mode,
            environment: environment,
            timeout: timeout
        )
        Self.logResult(result, hookName: kind, source: source, mode: mode, logger: logger)
    }

    // MARK: - Private

    private func preparedCommands(for kind: HookKind) -> [HookCommand]? {
        guard isMasterEnabled else { return nil }
        guard let settings = currentSettings() else { return nil }
        return settings.enabledCommands(for: kind)
    }

    private func currentSettings() -> HookSettings? {
        lock.lock()
        let mtime = persistence.modificationDate()
        if let cachedSettings, cachedModificationDate == mtime {
            defer { lock.unlock() }
            return cachedSettings
        }
        lock.unlock()

        let started = Date()
        let loaded = persistence.load()
        let elapsedMs = Int((Date().timeIntervalSince(started) * 1000).rounded())

        lock.lock()
        cachedSettings = loaded
        cachedModificationDate = mtime
        lock.unlock()

        if let loaded {
            let total = HookKind.allCases.reduce(0) { $0 + (loaded.hooks[$1]?.count ?? 0) }
            logger.log("hook config: loaded \(total) commands in \(elapsedMs)ms")
        } else {
            logger.log("hook config: no hooks.json (or empty), load took \(elapsedMs)ms")
        }
        return loaded
    }

    private struct RunResult {
        var spawnFailure: String?
        var exitCode: Int32 = 0
        var timedOut: Bool = false
        var spawnDuration: TimeInterval = 0
        var totalDuration: TimeInterval = 0
        var stderrSnippet: String?
        var stdoutSnippet: String?
    }

    private static func runProcess(
        source: HookCommand.Source,
        hookName: String,
        mode: String,
        environment: [String: String],
        timeout: TimeInterval
    ) -> RunResult {
        var result = RunResult()
        let runStarted = Date()

        let process = Process()
        switch source {
        case .command(let command):
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
        case .script(let scriptURL):
            let path = scriptURL.path
            guard FileManager.default.fileExists(atPath: path) else {
                result.spawnFailure = "script not found: \(path)"
                result.totalDuration = Date().timeIntervalSince(runStarted)
                return result
            }
            // If the file is executable, run it directly so its shebang line
            // picks the interpreter (lets users use python/ruby/etc.). Otherwise
            // fall back to /bin/sh <path> so users don't have to chmod +x.
            if FileManager.default.isExecutableFile(atPath: path) {
                process.executableURL = scriptURL
                process.arguments = []
            } else {
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = [path]
            }
        }

        var fullEnvironment = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            fullEnvironment[key] = value
        }
        process.environment = fullEnvironment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        let spawnStarted = Date()
        do {
            try process.run()
        } catch {
            result.spawnFailure = error.localizedDescription
            result.totalDuration = Date().timeIntervalSince(runStarted)
            return result
        }
        result.spawnDuration = Date().timeIntervalSince(spawnStarted)

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() >= deadline {
                process.terminate()
                Thread.sleep(forTimeInterval: 0.05)
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
                result.timedOut = true
                break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }

        let stdoutData = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
        let stderrData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
        try? stdoutPipe.fileHandleForReading.close()
        try? stderrPipe.fileHandleForReading.close()

        result.exitCode = process.terminationStatus
        result.totalDuration = Date().timeIntervalSince(runStarted)

        if result.exitCode != 0 || result.timedOut {
            let stderr = String(decoding: stderrData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let stdout = String(decoding: stdoutData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !stderr.isEmpty { result.stderrSnippet = String(stderr.prefix(400)) }
            else if !stdout.isEmpty { result.stdoutSnippet = String(stdout.prefix(400)) }
        }

        return result
    }

    private static func logResult(
        _ result: RunResult,
        hookName: String,
        source: HookCommand.Source,
        mode: String,
        logger: HookLogger
    ) {
        let sourceLabel: String
        switch source {
        case .command(let command):
            sourceLabel = "cmd=\"\(command)\""
        case .script(let url):
            sourceLabel = "script=\"\(url.path)\""
        }

        if let spawnFailure = result.spawnFailure {
            logger.log("hook \(hookName) [\(mode)]: failed to launch in \(formatMs(result.totalDuration)): \(spawnFailure) \(sourceLabel)")
            return
        }

        var line = "hook \(hookName) [\(mode)]: spawn=\(formatMs(result.spawnDuration)) total=\(formatMs(result.totalDuration)) exit=\(result.exitCode)"
        if result.timedOut {
            line += " timeout"
        }
        line += " \(sourceLabel)"
        if let stderrSnippet = result.stderrSnippet {
            line += " stderr=\(stderrSnippet)"
        } else if let stdoutSnippet = result.stdoutSnippet {
            line += " stdout=\(stdoutSnippet)"
        }
        logger.log(line)
    }

    private static func formatMs(_ duration: TimeInterval) -> String {
        "\(Int((duration * 1000).rounded()))ms"
    }
}
