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

    static let usageStatus = """
    liney status — report an agent's state for a pane (attention signal).

    USAGE:
      liney status <running|waiting|done|error> [--pane <uuid>]
                   [--title <text>] [--agent <name>]

    The pane defaults to $LINEY_PANE_ID (injected into every Liney pane), so
    inside an agent hook you can just run `liney status waiting`. No token is
    required — this is a self-report, the same trust level as `liney notify`.
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

    // MARK: - Status

    static func runStatus(
        arguments: [String],
        send: (Data) throws -> LineyControlResponse? = { try LineyControlClient.send(frame: $0) },
        environment: [String: String] = ProcessInfo.processInfo.environment,
        stdoutWriter: (String) -> Void = { print($0) },
        stderrWriter: (String) -> Void = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
    ) -> ExitCode {
        var state: String?
        var pane: String?
        var title: String?
        var agent: String?
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--pane":
                guard index + 1 < arguments.count else { return .usage }
                pane = arguments[index + 1]; index += 1
            case "--title":
                guard index + 1 < arguments.count else { return .usage }
                title = arguments[index + 1]; index += 1
            case "--agent":
                guard index + 1 < arguments.count else { return .usage }
                agent = arguments[index + 1]; index += 1
            case "-h", "--help":
                stdoutWriter(usageStatus); return .ok
            default:
                if argument.hasPrefix("-") {
                    stderrWriter("liney status: unknown flag '\(argument)'")
                    return .usage
                }
                if state == nil {
                    state = argument
                } else {
                    stderrWriter("liney status: unexpected positional '\(argument)'")
                    return .usage
                }
            }
            index += 1
        }
        guard let state, !state.isEmpty else {
            stderrWriter(usageStatus)
            return .usage
        }
        guard let normalized = AgentReportedState(cliValue: state) else {
            stderrWriter("liney status: unknown state '\(state)' (use running|waiting|done|error)")
            return .usage
        }
        // Pane is optional: when omitted the server falls back to the active
        // workspace. $LINEY_PANE_ID is the common path inside an agent hook.
        let resolvedPane = pane ?? environment[LineyAgentNotifyEnvironment.paneIDKey]

        // No token: status is unauthenticated like notify.
        let frame = encodeFrame(cmd: "status", token: nil, payload: [
            "state": normalized.rawValue,
            "pane": resolvedPane as Any?,
            "title": title as Any?,
            "agent": agent as Any?,
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
                    let statusText = session.status.map { " <\($0)>" } ?? ""
                    stdoutWriter("\(session.workspaceName)\(branchText)\(statusText) \(session.paneID) \(session.cwd)\(portText)")
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

    static let usageRead = """
    liney read — read the rendered terminal text of a pane.

    USAGE:
      liney read [--pane <uuid>] [--last <n>] [--scrollback]
                 [--wait-stable] [--token <t>] [--json]

    --wait-stable re-reads until the screen stops changing (good for letting an
    agent's TUI finish painting). The pane defaults to $LINEY_PANE_ID.
    """

    static let usageAgents = """
    liney agents — list panes with a detected or self-reported agent.

    USAGE:
      liney agents [--token <t>] [--json] [--no-color]
    """

    // MARK: - Read

    static func runRead(
        arguments: [String],
        send: (Data) throws -> LineyControlResponse? = { try LineyControlClient.send(frame: $0) },
        environment: [String: String] = ProcessInfo.processInfo.environment,
        stdoutWriter: (String) -> Void = { print($0) },
        stderrWriter: (String) -> Void = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) },
        sleeper: (UInt32) -> Void = { usleep($0) }
    ) -> ExitCode {
        var pane: String?
        var lastLines: Int?
        var scrollback = false
        var waitStable = false
        var token: String?
        var emitJSON = false
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--pane":
                guard index + 1 < arguments.count else { return .usage }
                pane = arguments[index + 1]; index += 1
            case "--last":
                guard index + 1 < arguments.count, let n = Int(arguments[index + 1]) else {
                    stderrWriter("liney read: --last requires an integer")
                    return .usage
                }
                lastLines = n; index += 1
            case "--scrollback":
                scrollback = true
            case "--wait-stable":
                waitStable = true
            case "--token":
                guard index + 1 < arguments.count else { return .usage }
                token = arguments[index + 1]; index += 1
            case "--json":
                emitJSON = true
            case "-h", "--help":
                stdoutWriter(usageRead); return .ok
            default:
                if argument.hasPrefix("-") {
                    stderrWriter("liney read: unknown flag '\(argument)'")
                    return .usage
                }
            }
            index += 1
        }
        // read is unauthenticated; pass a token only if one happens to be set.
        let resolvedToken = token ?? environment["LINEY_CONTROL_TOKEN"]
        let resolvedPane = pane ?? environment[LineyAgentNotifyEnvironment.paneIDKey]

        func readOnce() throws -> LineyControlResponse? {
            let frame = encodeFrame(cmd: "read", token: resolvedToken, payload: [
                "pane": resolvedPane as Any?,
                "lines": lastLines as Any?,
                "scrollback": scrollback ? true : nil as Any?,
            ])
            return try send(frame)
        }

        do {
            var response = try readOnce()
            if waitStable {
                // Poll until two consecutive reads return identical text, or we
                // exhaust the attempt budget. Polling lives in the CLI so the
                // app handler stays a fast, non-blocking snapshot.
                var previous = response?.text
                var attempts = 0
                let maxAttempts = 25
                while attempts < maxAttempts {
                    sleeper(200_000) // 200ms
                    let next = try readOnce()
                    if next?.text == previous { response = next; break }
                    previous = next?.text
                    response = next
                    attempts += 1
                }
            }
            guard let response else {
                stderrWriter("liney read: server returned no response")
                return .ioError
            }
            if !response.ok {
                stderrWriter("liney read: \(response.error ?? "unknown error")")
                return response.error == "token-mismatch" || response.error == "control-disabled"
                    ? .authRequired
                    : .ioError
            }
            if emitJSON {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = (try? encoder.encode(response)) ?? Data("{}".utf8)
                stdoutWriter(String(decoding: data, as: UTF8.self))
            } else {
                stdoutWriter(response.text ?? "")
            }
            return .ok
        } catch AgentNotifyError.socketUnavailable {
            stderrWriter("liney: Liney is not running")
            return .unavailable
        } catch {
            stderrWriter("liney read: \(error)")
            return .ioError
        }
    }

    // MARK: - Agents

    static func runAgents(
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
            case "--no-color":
                break // accepted for parity; text output is already plain
            case "-h", "--help":
                stdoutWriter(usageAgents); return .ok
            default:
                if argument.hasPrefix("-") {
                    stderrWriter("liney agents: unknown flag '\(argument)'")
                    return .usage
                }
            }
            index += 1
        }
        // agents is unauthenticated; pass a token only if one happens to be set.
        let resolvedToken = token ?? environment["LINEY_CONTROL_TOKEN"]
        let frame = encodeFrame(cmd: "agents", token: resolvedToken, payload: [:])
        do {
            let response = try send(frame)
            guard let response else {
                stderrWriter("liney agents: server returned no response")
                return .ioError
            }
            if !response.ok {
                stderrWriter("liney agents: \(response.error ?? "unknown error")")
                return .ioError
            }
            let agents = response.agents ?? []
            if emitJSON {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = (try? encoder.encode(agents)) ?? Data("[]".utf8)
                stdoutWriter(String(decoding: data, as: UTF8.self))
            } else {
                for agent in agents {
                    let typeText = agent.name ?? agent.type ?? "agent"
                    let branchText = agent.branch.map { ":\($0)" } ?? ""
                    let focusedText = agent.focused ? " *" : ""
                    let reportedText = agent.reported ? "" : " ~"
                    stdoutWriter("\(agent.status)\t\(typeText)\t\(agent.workspaceName)\(branchText)\t\(agent.paneID)\(focusedText)\(reportedText)")
                }
            }
            return .ok
        } catch AgentNotifyError.socketUnavailable {
            stderrWriter("liney: Liney is not running")
            return .unavailable
        } catch {
            stderrWriter("liney agents: \(error)")
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
