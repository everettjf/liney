//
//  AgentNotifyCLI.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

/// `liney notify` argument parser + entry point.
///
/// The same `Liney` executable is the GUI app (when launched without
/// arguments or via Finder) and the CLI client (when invoked with
/// `notify ...`). This keeps the install footprint to a single binary.
enum AgentNotifyCLI {
    struct Options: Equatable {
        var title: String?
        var body: String?
        var paneID: String?
        var workspaceID: String?
        var agentName: String?
        var showHelp: Bool = false
        var showVersion: Bool = false
    }

    enum ParseError: Error, Equatable {
        case unknownFlag(String)
        case missingValue(flag: String)
        case missingTitleAndBody
    }

    /// CLI exit codes. Stable for scripting.
    enum ExitCode: Int32 {
        case ok = 0
        case usage = 64       // EX_USAGE
        case unavailable = 69 // EX_UNAVAILABLE — server not reachable
        case ioError = 74     // EX_IOERR
    }

    /// Parses `liney notify` arguments. The leading `notify` token has already
    /// been consumed by the dispatch in `main.swift`.
    static func parse(arguments: [String]) throws -> Options {
        var options = Options()
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "-h", "--help":
                options.showHelp = true
            case "-V", "--version":
                options.showVersion = true
            case "-t", "--title":
                guard index + 1 < arguments.count else {
                    throw ParseError.missingValue(flag: argument)
                }
                options.title = arguments[index + 1]
                index += 1
            case "-b", "--body", "-m", "--message":
                guard index + 1 < arguments.count else {
                    throw ParseError.missingValue(flag: argument)
                }
                options.body = arguments[index + 1]
                index += 1
            case "-p", "--pane":
                guard index + 1 < arguments.count else {
                    throw ParseError.missingValue(flag: argument)
                }
                options.paneID = arguments[index + 1]
                index += 1
            case "-w", "--workspace":
                guard index + 1 < arguments.count else {
                    throw ParseError.missingValue(flag: argument)
                }
                options.workspaceID = arguments[index + 1]
                index += 1
            case "-a", "--agent":
                guard index + 1 < arguments.count else {
                    throw ParseError.missingValue(flag: argument)
                }
                options.agentName = arguments[index + 1]
                index += 1
            default:
                if argument.hasPrefix("-") {
                    throw ParseError.unknownFlag(argument)
                }
                // Bare positional → treat as the title if not already set,
                // otherwise append to body so `liney notify "Build" "succeeded"`
                // reads naturally.
                if options.title == nil {
                    options.title = argument
                } else if options.body == nil {
                    options.body = argument
                } else {
                    options.body = "\(options.body ?? "") \(argument)"
                }
            }
            index += 1
        }
        return options
    }

    /// Build a request from CLI options + the surrounding shell environment.
    /// Pulls `LINEY_PANE_ID` from the env when the caller did not pass one,
    /// so a notification fired from inside a Liney pane routes to that pane
    /// automatically.
    static func makeRequest(
        from options: Options,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> AgentNotifyRequest {
        let title = options.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let body = options.body?.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty && (body?.isEmpty != false) {
            throw ParseError.missingTitleAndBody
        }
        let paneID = options.paneID ?? environment[LineyAgentNotifyEnvironment.paneIDKey]
        return AgentNotifyRequest(
            title: title.isEmpty ? (body ?? "") : title,
            body: title.isEmpty ? nil : body,
            paneID: paneID.flatMap { $0.isEmpty ? nil : $0 },
            workspaceID: options.workspaceID.flatMap { $0.isEmpty ? nil : $0 },
            agentName: options.agentName.flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    static let usageText = """
    liney notify — send a desktop notification to the running Liney app.

    USAGE:
      liney notify [TITLE] [BODY]
      liney notify --title <text> [--body <text>] [--pane <uuid>]
                   [--workspace <uuid>] [--agent <name>]

    OPTIONS:
      -t, --title <text>     Notification title (required if no positional)
      -b, --body  <text>     Notification body (alias: -m, --message)
      -p, --pane  <uuid>     Originating pane (defaults to $LINEY_PANE_ID)
      -w, --workspace <uuid> Originating workspace
      -a, --agent <name>     Agent display name (e.g. Claude, Codex)
      -V, --version          Print Liney version and exit
      -h, --help             Show this help and exit

    The CLI talks to the running Liney app over a Unix domain socket at
    ~/Library/Application Support/Liney/agent-notify.sock. If Liney is not
    running, the command exits with status 69 (EX_UNAVAILABLE).
    """

    /// Top-level CLI runner. Returns an exit code; the dispatcher in
    /// `main.swift` calls `exit(_)` with the returned value.
    static func run(
        arguments: [String],
        send: (AgentNotifyRequest) throws -> Void = { try AgentNotifyClient.send($0) },
        stdoutWriter: (String) -> Void = { print($0) },
        stderrWriter: (String) -> Void = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) },
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ExitCode {
        let options: Options
        do {
            options = try parse(arguments: arguments)
        } catch ParseError.unknownFlag(let flag) {
            stderrWriter("liney notify: unknown flag '\(flag)'")
            stderrWriter(usageText)
            return .usage
        } catch ParseError.missingValue(let flag) {
            stderrWriter("liney notify: flag '\(flag)' requires a value")
            return .usage
        } catch {
            stderrWriter("liney notify: \(error)")
            return .usage
        }

        if options.showHelp {
            stdoutWriter(usageText)
            return .ok
        }
        if options.showVersion {
            let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
            stdoutWriter("liney notify v\(version)")
            return .ok
        }

        let request: AgentNotifyRequest
        do {
            request = try makeRequest(from: options, environment: environment)
        } catch ParseError.missingTitleAndBody {
            stderrWriter("liney notify: a title or body is required")
            stderrWriter(usageText)
            return .usage
        } catch {
            stderrWriter("liney notify: \(error)")
            return .usage
        }

        do {
            try send(request)
            return .ok
        } catch AgentNotifyError.socketUnavailable {
            stderrWriter("liney notify: Liney is not running (no socket at ~/Library/Application Support/Liney/agent-notify.sock)")
            return .unavailable
        } catch AgentNotifyError.payloadTooLarge(let limit, let actual) {
            stderrWriter("liney notify: payload too large (\(actual) > \(limit) bytes)")
            return .ioError
        } catch AgentNotifyError.socketWriteFailed(let code) {
            stderrWriter("liney notify: write failed (errno \(code))")
            return .ioError
        } catch {
            stderrWriter("liney notify: \(error)")
            return .ioError
        }
    }
}
