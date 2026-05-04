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
    case open
    case split
    case sendKeys = "send-keys"
    case sessionList = "session-list"
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

/// Response shape for a single pane in `session-list`.
struct LineyControlSession: Codable, Equatable {
    var workspaceID: String
    var workspaceName: String
    var paneID: String
    var cwd: String
    var branch: String?
    var listeningPorts: [Int]

    enum CodingKeys: String, CodingKey {
        case workspaceID = "workspace"
        case workspaceName = "workspaceName"
        case paneID = "pane"
        case cwd
        case branch
        case listeningPorts = "ports"
    }
}

/// Generic response written back to the CLI client.
struct LineyControlResponse: Codable, Equatable {
    var ok: Bool
    var error: String?
    var sessions: [LineyControlSession]?

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
