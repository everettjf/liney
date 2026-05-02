//
//  HookRunner.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

/// Fires user-defined lifecycle hooks. Spawns each command via `/bin/sh -c`,
/// passes context as environment variables, and logs failures to
/// `~/.liney/hook.log`. Hooks are gated on `AppSettings.hooksEnabled` (off by
/// default) — when disabled, `fire(_:context:)` is a no-op even if the file
/// exists.
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

    /// Per-command soft timeout for async hooks. We still fire-and-forget but
    /// kill the child after this so a sleep loop doesn't pile up zombies.
    static let asyncCommandTimeout: TimeInterval = 30.0

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

    /// Fire a hook asynchronously. Returns immediately; commands run in the
    /// background. Use this for everything except `app.on_quit`.
    func fire(_ kind: HookKind, context: HookContext) {
        guard let commands = preparedCommands(for: kind) else { return }
        guard !commands.isEmpty else { return }

        let env = context.environmentVariables(for: kind)
        let name = kind.rawValue
        let logger = self.logger
        queue.async {
            for command in commands {
                Self.runCommand(
                    command: command.command,
                    hookName: name,
                    environment: env,
                    timeout: Self.asyncCommandTimeout,
                    logger: logger
                )
            }
        }
    }

    /// Fire a hook and block (with `timeout` total) for completion. Used for
    /// `app.on_quit` so user cleanup gets a chance to run before exit. If the
    /// timeout elapses, lingering child processes are terminated.
    func fireBlocking(_ kind: HookKind, context: HookContext, timeout: TimeInterval) {
        guard let commands = preparedCommands(for: kind) else { return }
        guard !commands.isEmpty else { return }

        let env = context.environmentVariables(for: kind)
        let name = kind.rawValue
        let deadline = Date().addingTimeInterval(timeout)
        for command in commands {
            let remaining = max(0.05, deadline.timeIntervalSinceNow)
            Self.runCommand(
                command: command.command,
                hookName: name,
                environment: env,
                timeout: remaining,
                logger: logger
            )
            if Date() >= deadline {
                logger.log("hook \(name): aborted remaining commands (timeout)")
                break
            }
        }
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

        let loaded = persistence.load()
        lock.lock()
        cachedSettings = loaded
        cachedModificationDate = mtime
        lock.unlock()
        return loaded
    }

    private static func runCommand(
        command: String,
        hookName: String,
        environment: [String: String],
        timeout: TimeInterval,
        logger: HookLogger
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]

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

        do {
            try process.run()
        } catch {
            logger.log("hook \(hookName): failed to launch \"\(command)\": \(error.localizedDescription)")
            return
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() >= deadline {
                process.terminate()
                Thread.sleep(forTimeInterval: 0.05)
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
                logger.log("hook \(hookName): timed out after \(Int(timeout))s, terminated: \"\(command)\"")
                break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }

        let stdoutData = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
        let stderrData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
        try? stdoutPipe.fileHandleForReading.close()
        try? stderrPipe.fileHandleForReading.close()

        let exitCode = process.terminationStatus
        if exitCode != 0 {
            let stderr = String(decoding: stderrData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let stdout = String(decoding: stdoutData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var summary = "hook \(hookName): exit \(exitCode) for \"\(command)\""
            if !stderr.isEmpty {
                summary += " | stderr: \(stderr.prefix(400))"
            } else if !stdout.isEmpty {
                summary += " | stdout: \(stdout.prefix(400))"
            }
            logger.log(summary)
        }
    }
}
