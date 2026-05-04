//
//  LineyControlCLI.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

/// Argument parsing + IPC wiring for non-notify CLI subcommands:
///   liney open <repo> [--worktree <path>] [--token <t>]
///   liney split [--axis vertical|horizontal] [--placement after|before]
///                [--pane <uuid>] [--token <t>]
///   liney send-keys <pane> <text> [--token <t>]
///   liney session list [--token <t>] [--json]
///
/// Token lookup falls back to `LINEY_CONTROL_TOKEN` so users don't need to
/// retype it. The CLI emits structured JSON to stdout for `session list` so
/// it composes with `jq` / `awk`.
enum LineyControlCLI {
    /// Returned exit codes (stable for scripting).
    enum ExitCode: Int32 {
        case ok = 0
        case usage = 64
        case unavailable = 69
        case ioError = 74
        case authRequired = 77 // EX_NOPERM
    }

    enum CLIError: Error, Equatable {
        case missingArgument(name: String)
        case unknownFlag(String)
    }

    static let usageOpen = """
    liney open — open a repository in the running Liney app.

    USAGE:
      liney open <repo> [--worktree <path>] [--token <t>]
    """

    static let usageSplit = """
    liney split — split the focused pane in the running Liney app.

    USAGE:
      liney split [--axis vertical|horizontal] [--placement after|before]
                  [--pane <uuid>] [--token <t>]
    """

    static let usageSendKeys = """
    liney send-keys — send literal text to a pane.

    USAGE:
      liney send-keys <pane-uuid> <text> [--token <t>]
      liney send-keys --pane <uuid> --text "<text>" [--token <t>]
    """

    static let usageSessionList = """
    liney session list — list every running pane across all workspaces.

    USAGE:
      liney session list [--token <t>] [--json]
    """

    // MARK: - Open

    static func runOpen(
        arguments: [String],
        send: (Data) throws -> LineyControlResponse? = { try LineyControlClient.send(frame: $0) },
        environment: [String: String] = ProcessInfo.processInfo.environment,
        stdoutWriter: (String) -> Void = { print($0) },
        stderrWriter: (String) -> Void = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
    ) -> ExitCode {
        var repo: String?
        var worktree: String?
        var token: String?
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--worktree":
                guard index + 1 < arguments.count else {
                    stderrWriter("liney open: --worktree requires a value")
                    return .usage
                }
                worktree = arguments[index + 1]
                index += 1
            case "--token":
                guard index + 1 < arguments.count else {
                    stderrWriter("liney open: --token requires a value")
                    return .usage
                }
                token = arguments[index + 1]
                index += 1
            case "-h", "--help":
                stdoutWriter(usageOpen)
                return .ok
            default:
                if argument.hasPrefix("-") {
                    stderrWriter("liney open: unknown flag '\(argument)'")
                    return .usage
                }
                if repo == nil {
                    repo = argument
                } else {
                    stderrWriter("liney open: unexpected positional '\(argument)'")
                    return .usage
                }
            }
            index += 1
        }
        guard let repo, !repo.isEmpty else {
            stderrWriter(usageOpen)
            return .usage
        }
        let resolvedToken = token ?? environment["LINEY_CONTROL_TOKEN"]
        guard let resolvedToken, !resolvedToken.isEmpty else {
            stderrWriter("liney open: --token (or LINEY_CONTROL_TOKEN) is required")
            return .authRequired
        }

        let frame = encodeFrame(cmd: "open", token: resolvedToken, payload: [
            "repo": repo,
            "worktree": worktree as Any?,
        ])
        return runDispatch(frame: frame, send: send, stdoutWriter: stdoutWriter, stderrWriter: stderrWriter)
    }

    // MARK: - Split

    static func runSplit(
        arguments: [String],
        send: (Data) throws -> LineyControlResponse? = { try LineyControlClient.send(frame: $0) },
        environment: [String: String] = ProcessInfo.processInfo.environment,
        stdoutWriter: (String) -> Void = { print($0) },
        stderrWriter: (String) -> Void = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
    ) -> ExitCode {
        var axis: String?
        var placement: String?
        var pane: String?
        var token: String?
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--axis":
                guard index + 1 < arguments.count else { return .usage }
                axis = arguments[index + 1]; index += 1
            case "--placement":
                guard index + 1 < arguments.count else { return .usage }
                placement = arguments[index + 1]; index += 1
            case "--pane":
                guard index + 1 < arguments.count else { return .usage }
                pane = arguments[index + 1]; index += 1
            case "--token":
                guard index + 1 < arguments.count else { return .usage }
                token = arguments[index + 1]; index += 1
            case "-h", "--help":
                stdoutWriter(usageSplit); return .ok
            default:
                if argument.hasPrefix("-") {
                    stderrWriter("liney split: unknown flag '\(argument)'")
                    return .usage
                }
            }
            index += 1
        }
        let resolvedToken = token ?? environment["LINEY_CONTROL_TOKEN"]
        guard let resolvedToken, !resolvedToken.isEmpty else {
            stderrWriter("liney split: --token (or LINEY_CONTROL_TOKEN) is required")
            return .authRequired
        }
        let resolvedPane = pane ?? environment[LineyAgentNotifyEnvironment.paneIDKey]

        let frame = encodeFrame(cmd: "split", token: resolvedToken, payload: [
            "axis": axis as Any?,
            "placement": placement as Any?,
            "pane": resolvedPane as Any?,
        ])
        return runDispatch(frame: frame, send: send, stdoutWriter: stdoutWriter, stderrWriter: stderrWriter)
    }

    // MARK: - Send keys

    static func runSendKeys(
        arguments: [String],
        send: (Data) throws -> LineyControlResponse? = { try LineyControlClient.send(frame: $0) },
        environment: [String: String] = ProcessInfo.processInfo.environment,
        stdoutWriter: (String) -> Void = { print($0) },
        stderrWriter: (String) -> Void = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
    ) -> ExitCode {
        var pane: String?
        var text: String?
        var token: String?
        var index = 0
        var positional: [String] = []
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--pane":
                guard index + 1 < arguments.count else { return .usage }
                pane = arguments[index + 1]; index += 1
            case "--text":
                guard index + 1 < arguments.count else { return .usage }
                text = arguments[index + 1]; index += 1
            case "--token":
                guard index + 1 < arguments.count else { return .usage }
                token = arguments[index + 1]; index += 1
            case "-h", "--help":
                stdoutWriter(usageSendKeys); return .ok
            default:
                if argument.hasPrefix("-") {
                    stderrWriter("liney send-keys: unknown flag '\(argument)'")
                    return .usage
                }
                positional.append(argument)
            }
            index += 1
        }
        if pane == nil { pane = positional.first }
        if text == nil, positional.count >= 2 { text = positional[1] }
        let resolvedPane = pane ?? environment[LineyAgentNotifyEnvironment.paneIDKey]
        guard let resolvedPane, !resolvedPane.isEmpty else {
            stderrWriter("liney send-keys: pane is required (positional or --pane or $LINEY_PANE_ID)")
            return .usage
        }
        guard let text, !text.isEmpty else {
            stderrWriter("liney send-keys: text is required")
            return .usage
        }
        let resolvedToken = token ?? environment["LINEY_CONTROL_TOKEN"]
        guard let resolvedToken, !resolvedToken.isEmpty else {
            stderrWriter("liney send-keys: --token (or LINEY_CONTROL_TOKEN) is required")
            return .authRequired
        }

        let frame = encodeFrame(cmd: "send-keys", token: resolvedToken, payload: [
            "pane": resolvedPane,
            "text": text,
        ])
        return runDispatch(frame: frame, send: send, stdoutWriter: stdoutWriter, stderrWriter: stderrWriter)
    }

    // MARK: - Session list

    static func runSessionList(
        arguments: [String],
        send: (Data) throws -> LineyControlResponse? = { try LineyControlClient.send(frame: $0) },
        environment: [String: String] = ProcessInfo.processInfo.environment,
        stdoutWriter: (String) -> Void = { print($0) },
        stderrWriter: (String) -> Void = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
    ) -> ExitCode {
        var token: String?
        var emitJSON = false
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--token":
                guard index + 1 < arguments.count else { return .usage }
                token = arguments[index + 1]; index += 1
            case "--json":
                emitJSON = true
            case "-h", "--help":
                stdoutWriter(usageSessionList); return .ok
            default:
                if argument.hasPrefix("-") {
                    stderrWriter("liney session: unknown flag '\(argument)'")
                    return .usage
                }
            }
            index += 1
        }
        let resolvedToken = token ?? environment["LINEY_CONTROL_TOKEN"]
        guard let resolvedToken, !resolvedToken.isEmpty else {
            stderrWriter("liney session list: --token (or LINEY_CONTROL_TOKEN) is required")
            return .authRequired
        }
        let frame = encodeFrame(cmd: "session-list", token: resolvedToken, payload: [:])
        do {
            let response = try send(frame)
            guard let response else {
                stderrWriter("liney session list: server returned no response")
                return .ioError
            }
            if !response.ok {
                stderrWriter("liney session list: \(response.error ?? "unknown error")")
                return .ioError
            }
            let sessions = response.sessions ?? []
            if emitJSON {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = (try? encoder.encode(sessions)) ?? Data("[]".utf8)
                stdoutWriter(String(decoding: data, as: UTF8.self))
            } else {
                for session in sessions {
                    let portText = session.listeningPorts.isEmpty
                        ? ""
                        : " ports=" + session.listeningPorts.map { ":\($0)" }.joined(separator: ",")
                    let branchText = session.branch.map { " [\($0)]" } ?? ""
                    stdoutWriter("\(session.workspaceName)\(branchText) \(session.paneID) \(session.cwd)\(portText)")
                }
            }
            return .ok
        } catch AgentNotifyError.socketUnavailable {
            stderrWriter("liney: Liney is not running")
            return .unavailable
        } catch {
            stderrWriter("liney session list: \(error)")
            return .ioError
        }
    }

    // MARK: - Helpers

    private static func runDispatch(
        frame: Data,
        send: (Data) throws -> LineyControlResponse?,
        stdoutWriter: (String) -> Void,
        stderrWriter: (String) -> Void
    ) -> ExitCode {
        do {
            let response = try send(frame)
            guard let response else { return .ok }
            if response.ok { return .ok }
            stderrWriter("liney: \(response.error ?? "unknown error")")
            return response.error == "token-mismatch" || response.error == "control-disabled"
                ? .authRequired
                : .ioError
        } catch AgentNotifyError.socketUnavailable {
            stderrWriter("liney: Liney is not running")
            return .unavailable
        } catch {
            stderrWriter("liney: \(error)")
            return .ioError
        }
    }

    /// Encodes a control envelope. JSONSerialization keeps things permissive
    /// about optional fields (omitted when nil) so the wire stays clean.
    static func encodeFrame(
        cmd: String,
        token: String?,
        payload: [String: Any?]
    ) -> Data {
        var dict: [String: Any] = [
            "v": 1,
            "cmd": cmd,
        ]
        if let token, !token.isEmpty {
            dict["token"] = token
        }
        for (key, value) in payload {
            if let value {
                dict[key] = value
            }
        }
        guard var data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]) else {
            return Data()
        }
        data.append(0x0A)
        return data
    }
}
