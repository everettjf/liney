//
//  HookSettings.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

/// One of the four lifecycle points where a user-defined hook can fire.
enum HookKind: String, Codable, CaseIterable, Hashable {
    case appOnLaunch = "app.on_launch"
    case appOnQuit = "app.on_quit"
    case sessionOnStart = "session.on_start"
    case sessionOnExit = "session.on_exit"
}

/// A single command attached to a hook point. Exactly one of `command`
/// (inline shell, passed to `/bin/sh -c`) or `script` (path to a shell
/// script file) should be set. If both are set, `script` wins.
///
/// `sync` controls whether the caller waits for the command to finish before
/// returning (true), or whether the command is dispatched and the caller
/// continues immediately (false, default). Sync mode is useful when a hook's
/// side effect must complete before downstream work begins (e.g. inject env
/// before a session takes over the terminal); async mode is appropriate when
/// the command's outcome doesn't gate anything else.
///
/// `timeoutSeconds` overrides the per-mode default. nil → 5s for sync, 30s
/// for async. The hook process is force-terminated after the timeout.
struct HookCommand: Codable, Hashable {
    static let defaultAsyncTimeout: TimeInterval = 30
    static let defaultSyncTimeout: TimeInterval = 5

    /// Resolved source of the hook — either an inline shell command string, or
    /// a path to a script file on disk.
    enum Source: Hashable {
        case command(String)
        case script(URL)
    }

    var enabled: Bool
    var sync: Bool
    var command: String?
    var script: String?
    var timeoutSeconds: Double?

    init(
        enabled: Bool = true,
        sync: Bool = false,
        command: String? = nil,
        script: String? = nil,
        timeoutSeconds: Double? = nil
    ) {
        self.enabled = enabled
        self.sync = sync
        self.command = command
        self.script = script
        self.timeoutSeconds = timeoutSeconds
    }

    var effectiveTimeout: TimeInterval {
        if let timeoutSeconds, timeoutSeconds > 0 {
            return TimeInterval(timeoutSeconds)
        }
        return sync ? Self.defaultSyncTimeout : Self.defaultAsyncTimeout
    }

    /// Whether the command has any executable content. Empty / whitespace-only
    /// fields and missing-file scripts are treated as "no source" so the
    /// runner skips and (for script) logs a clear error.
    var hasContent: Bool {
        if let script, !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if let command, !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return false
    }

    /// Resolve the source. Script paths support `~` expansion; relative paths
    /// resolve under `~/.liney/`. Returns nil if neither field has content.
    /// The runner is responsible for reporting non-existent script files.
    func resolvedSource(stateDirectory: URL) -> Source? {
        if let script {
            let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return .script(Self.resolveScriptPath(trimmed, stateDirectory: stateDirectory))
            }
        }
        if let command {
            let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return .command(trimmed)
            }
        }
        return nil
    }

    static func resolveScriptPath(_ rawPath: String, stateDirectory: URL) -> URL {
        let expanded = (rawPath as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded)
        }
        return stateDirectory.appendingPathComponent(expanded, isDirectory: false)
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case sync
        case command
        case script
        case timeoutSeconds
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        let sync = try container.decodeIfPresent(Bool.self, forKey: .sync) ?? false
        let command = try container.decodeIfPresent(String.self, forKey: .command)
        let script = try container.decodeIfPresent(String.self, forKey: .script)
        let timeout = try container.decodeIfPresent(Double.self, forKey: .timeoutSeconds)
        self.init(
            enabled: enabled,
            sync: sync,
            command: command,
            script: script,
            timeoutSeconds: timeout
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(sync, forKey: .sync)
        try container.encodeIfPresent(command, forKey: .command)
        try container.encodeIfPresent(script, forKey: .script)
        try container.encodeIfPresent(timeoutSeconds, forKey: .timeoutSeconds)
    }
}

/// User configuration loaded from `~/.liney/hooks.json`.
struct HookSettings: Codable, Hashable {
    static let currentVersion = 1

    var version: Int
    var hooks: [HookKind: [HookCommand]]

    init(version: Int = HookSettings.currentVersion, hooks: [HookKind: [HookCommand]] = [:]) {
        self.version = version
        var normalized: [HookKind: [HookCommand]] = [:]
        for kind in HookKind.allCases {
            normalized[kind] = hooks[kind] ?? []
        }
        self.hooks = normalized
    }

    /// Empty config — all hook lists exist but contain no commands.
    static var empty: HookSettings { HookSettings() }

    /// Sample config used for "Reveal in Finder" / first-time scaffolding.
    static var sample: HookSettings {
        HookSettings(
            hooks: [
                .appOnLaunch: [
                    HookCommand(enabled: false, sync: false, command: "echo \"liney launched at $(date)\" >> ~/.liney/hook.log")
                ],
                .appOnQuit: [],
                .sessionOnStart: [
                    HookCommand(enabled: false, sync: false, command: "echo \"async: session $LINEY_SESSION_ID started in $LINEY_SESSION_CWD\" >> ~/.liney/hook.log"),
                    HookCommand(enabled: false, sync: true, command: "echo \"sync: blocks the caller; should be fast\" >> ~/.liney/hook.log", timeoutSeconds: 5),
                    HookCommand(enabled: false, sync: false, script: "hooks/session-start.sh")
                ],
                .sessionOnExit: []
            ]
        )
    }

    func enabledCommands(for kind: HookKind) -> [HookCommand] {
        (hooks[kind] ?? []).filter { $0.enabled && $0.hasContent }
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case hooks
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(Int.self, forKey: .version) ?? HookSettings.currentVersion
        let raw = try container.decodeIfPresent([String: [HookCommand]].self, forKey: .hooks) ?? [:]
        var hooks: [HookKind: [HookCommand]] = [:]
        for (key, value) in raw {
            guard let kind = HookKind(rawValue: key) else { continue }
            hooks[kind] = value
        }
        self.init(version: version, hooks: hooks)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        var raw: [String: [HookCommand]] = [:]
        for kind in HookKind.allCases {
            raw[kind.rawValue] = hooks[kind] ?? []
        }
        try container.encode(raw, forKey: .hooks)
    }
}

/// Context handed to a fired hook. Becomes environment variables in the spawned process.
struct HookContext {
    var appVersion: String
    var sessionID: String?
    var sessionCWD: String?
    var sessionShell: String?
    var sessionBackend: String?
    var sessionExitCode: Int32?

    static func app(appVersion: String) -> HookContext {
        HookContext(appVersion: appVersion)
    }

    func environmentVariables(for kind: HookKind) -> [String: String] {
        var env: [String: String] = [
            "LINEY_HOOK": kind.rawValue,
            "LINEY_APP_VERSION": appVersion,
        ]
        if let sessionID { env["LINEY_SESSION_ID"] = sessionID }
        if let sessionCWD { env["LINEY_SESSION_CWD"] = sessionCWD }
        if let sessionShell { env["LINEY_SESSION_SHELL"] = sessionShell }
        if let sessionBackend { env["LINEY_SESSION_BACKEND"] = sessionBackend }
        if let sessionExitCode { env["LINEY_SESSION_EXIT_CODE"] = String(sessionExitCode) }
        return env
    }
}
