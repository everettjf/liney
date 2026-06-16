//
//  LineyControlProtocol.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

/// Multi-command IPC protocol layered on top of `AgentNotifyServer`.
///
/// The wire format remains a single newline-terminated JSON object per
/// connection. The `cmd` field discriminates: when absent it defaults to
/// `notify` so already-released `liney notify` clients keep working without
/// modification.
///
/// All commands other than `notify` require a token that matches the value
/// stored under `LineyURLScheme` (Settings → URL Scheme). This piggybacks on
/// the existing trust boundary the user already configured for the
/// `liney://` URL handler — no second password to manage.
enum LineyControlCommand: String, Codable {
    case notify
    case status
    case open
    case split
    case sendKeys = "send-keys"
    case sessionList = "session-list"
    case read
    case agents

    /// Whether the command must carry the trust token. The self-reports
    /// (`notify` / `status`) and the read-only inspection commands
    /// (`read` / `agents` / `session list`) do not — they mutate no app state
    /// and the control socket is already owner-only. The mutating control
    /// commands do.
    var requiresControlToken: Bool {
        switch self {
        case .notify, .status, .read, .agents, .sessionList:
            return false
        case .open, .split, .sendKeys:
            return true
        }
    }
}

/// State an agent reports about its pane. Mirrors `IslandItemStatus` but is
/// part of the stable wire contract, so it owns its own raw values and a
/// permissive CLI parser for the handful of synonyms agents tend to emit.
enum AgentReportedState: String, Codable, Equatable {
    case running
    case waiting
    case done
    case error

    /// Maps the wire state to the dynamic-island presentation status.
    var islandStatus: IslandItemStatus {
        switch self {
        case .running: return .running
        case .waiting: return .waitingForInput
        case .done: return .done
        case .error: return .error
        }
    }

    /// Parses a user/agent-supplied token, accepting the common synonyms so a
    /// hook author does not have to memorize the canonical four. Returns nil
    /// for anything unrecognized so the CLI can reject it with a usage error.
    init?(cliValue raw: String) {
        switch raw.lowercased() {
        case "running", "busy", "working", "start", "started":
            self = .running
        case "waiting", "wait", "blocked", "input", "needs-input":
            self = .waiting
        case "done", "complete", "completed", "finished", "success", "ok":
            self = .done
        case "error", "failed", "fail":
            self = .error
        default:
            return nil
        }
    }
}

/// Light envelope that decodes only the discriminator + auth fields. The
/// dispatcher decodes the same JSON a second time into the typed payload
/// once `cmd` is known.
struct LineyControlEnvelope: Decodable {
    var version: Int?
    var cmd: LineyControlCommand?
    var token: String?

    enum CodingKeys: String, CodingKey {
        case version = "v"
        case cmd
        case token
    }
}

/// Open a repository (and optionally a worktree) in the running app.
struct LineyOpenRequest: Decodable {
    var repo: String
    var worktree: String?
}

/// Split the focused pane (or a specific pane) along an axis.
struct LineySplitRequest: Decodable {
    var pane: String?
    var axis: String?       // "vertical" | "horizontal" — defaults to vertical
    var placement: String?  // "after" | "before" — defaults to after
}

/// Report an agent's current state for a pane. Like `notify`, this is an
/// unauthenticated, fire-and-forget signal a pane emits about itself: it sets
/// the pane's attention status (surfaced in the dynamic island and
/// `session-list`) but grants no control over the app.
struct LineyStatusRequest: Decodable {
    var state: String
    var pane: String?       // defaults to $LINEY_PANE_ID at the CLI
    var title: String?      // optional label, e.g. "Needs approval to deploy"
    var agentName: String?

    enum CodingKeys: String, CodingKey {
        case state
        case pane
        case title
        case agentName = "agent"
    }
}

/// Send literal text to a pane. Text is UTF-8; control characters are passed
/// through as-is so callers can append `\n` to submit, `\u{0003}` for
/// Ctrl-C, etc.
struct LineySendKeysRequest: Decodable {
    var pane: String?       // defaults to focused pane
    var text: String
}

/// Request a JSON snapshot of every running pane across all workspaces.
struct LineySessionListRequest: Decodable {
    // Reserved for filtering options; intentionally empty for v1.
}

/// Read the rendered terminal text of a pane.
struct LineyReadRequest: Decodable {
    var pane: String?       // defaults to the focused pane
    var lines: Int?         // keep only the last N non-empty lines
    var scrollback: Bool?   // include history beyond the viewport
}

/// List panes that currently have a detected or self-reported agent.
struct LineyAgentsRequest: Decodable {
    // Reserved for filtering options; intentionally empty for v1.
}

/// One detected agent pane in the `agents` response.
struct LineyAgentInfo: Codable, Equatable {
    var workspaceID: String
    var workspaceName: String
    var paneID: String
    /// Normalized agent type, e.g. "claude-code", "codex" (nil if only known
    /// via a self-report that didn't name the agent).
    var type: String?
    /// Human-facing name, e.g. "Claude Code".
    var name: String?
    /// "running" | "waiting" | "done" | "error".
    var status: String
    /// True when `status` came from a `liney status` self-report rather than
    /// passive process detection.
    var reported: Bool
    var cwd: String
    var branch: String?
    var focused: Bool

    enum CodingKeys: String, CodingKey {
        case workspaceID = "workspace"
        case workspaceName = "workspaceName"
        case paneID = "pane"
        case type
        case name
        case status
        case reported
        case cwd
        case branch
        case focused
    }
}

/// Response shape for a single pane in `session-list`.
struct LineyControlSession: Codable, Equatable {
    var workspaceID: String
    var workspaceName: String
    var paneID: String
    var cwd: String
    var branch: String?
    var listeningPorts: [Int]
    /// Last state the pane's agent reported via `liney status`, if any.
    var status: String? = nil

    enum CodingKeys: String, CodingKey {
        case workspaceID = "workspace"
        case workspaceName = "workspaceName"
        case paneID = "pane"
        case cwd
        case branch
        case listeningPorts = "ports"
        case status
    }
}

/// Generic response written back to the CLI client.
struct LineyControlResponse: Codable, Equatable {
    var ok: Bool
    var error: String?
    var sessions: [LineyControlSession]?
    /// Rendered terminal text for `read`.
    var text: String?
    /// Number of lines in `text` for `read`.
    var lineCount: Int?
    /// Detected agent panes for `agents`.
    var agents: [LineyAgentInfo]?

    static let success = LineyControlResponse(ok: true)

    static func failure(_ message: String) -> LineyControlResponse {
        LineyControlResponse(ok: false, error: message)
    }
}

enum LineyControlEncoder {
    static let json: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static func encodeResponse(_ response: LineyControlResponse) -> Data {
        (try? json.encode(response)) ?? Data("{\"ok\":false,\"error\":\"encode-failed\"}".utf8)
    }
}
