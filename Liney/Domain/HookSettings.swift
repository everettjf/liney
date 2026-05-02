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

/// A single command attached to a hook point. `command` is passed to `/bin/sh -c`.
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

    var enabled: Bool
    var sync: Bool
    var command: String
    var timeoutSeconds: Double?

    init(
        enabled: Bool = true,
        sync: Bool = false,
        command: String,
        timeoutSeconds: Double? = nil
    ) {
        self.enabled = enabled
        self.sync = sync
        self.command = command
        self.timeoutSeconds = timeoutSeconds
    }

    var effectiveTimeout: TimeInterval {
        if let timeoutSeconds, timeoutSeconds > 0 {
            return TimeInterval(timeoutSeconds)
        }
        return sync ? Self.defaultSyncTimeout : Self.defaultAsyncTimeout
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case sync
        case command
        case timeoutSeconds
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        let sync = try container.decodeIfPresent(Bool.self, forKey: .sync) ?? false
        let command = try container.decodeIfPresent(String.self, forKey: .command) ?? ""
        let timeout = try container.decodeIfPresent(Double.self, forKey: .timeoutSeconds)
        self.init(enabled: enabled, sync: sync, command: command, timeoutSeconds: timeout)
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
                    HookCommand(enabled: false, sync: true, command: "echo \"sync: blocks the caller; should be fast\" >> ~/.liney/hook.log", timeoutSeconds: 5)
                ],
                .sessionOnExit: []
            ]
        )
    }

    func enabledCommands(for kind: HookKind) -> [HookCommand] {
        (hooks[kind] ?? []).filter { $0.enabled && !$0.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
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
