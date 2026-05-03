//
//  AgentNotifyProtocol.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

/// Environment variables Liney injects into PTY sessions so out-of-band agent
/// notifications (delivered via the `liney notify` CLI) can be routed back to
/// the originating pane.
enum LineyAgentNotifyEnvironment {
    static let paneIDKey = "LINEY_PANE_ID"
}

/// Wire format for a single agent notification.
///
/// One frame is one JSON object on its own line, UTF-8 encoded, terminated by
/// `\n`. Forward-compatible: unknown fields are ignored, missing optional
/// fields default to nil. The `version` field is reserved so future protocol
/// breakages can be flagged.
struct AgentNotifyRequest: Codable, Equatable {
    /// Wire-format version. Bump only on incompatible changes.
    static let currentVersion: Int = 1

    var version: Int
    var title: String
    var body: String?
    var paneID: String?
    var workspaceID: String?
    var agentName: String?

    enum CodingKeys: String, CodingKey {
        case version = "v"
        case title
        case body
        case paneID = "pane"
        case workspaceID = "workspace"
        case agentName = "agent"
    }

    init(
        version: Int = AgentNotifyRequest.currentVersion,
        title: String,
        body: String? = nil,
        paneID: String? = nil,
        workspaceID: String? = nil,
        agentName: String? = nil
    ) {
        self.version = version
        self.title = title
        self.body = body
        self.paneID = paneID
        self.workspaceID = workspaceID
        self.agentName = agentName
    }
}

/// Errors the protocol layer surfaces to callers.
enum AgentNotifyError: Error, Equatable {
    case missingTitle
    case payloadTooLarge(limit: Int, actual: Int)
    case decode(message: String)
    case socketUnavailable
    case socketWriteFailed(errno: Int32)
}

enum AgentNotifyProtocol {
    /// Maximum frame size accepted by the server. A notification with a
    /// 1 MB body is already absurd; cap well below that to make a runaway
    /// or hostile client easy to reject.
    static let maxFrameBytes: Int = 64 * 1024

    /// Encode a request as a UTF-8 JSON frame terminated by `\n`.
    static func encode(_ request: AgentNotifyRequest) throws -> Data {
        guard !request.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || (request.body?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) else {
            throw AgentNotifyError.missingTitle
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(request)
        if data.count >= maxFrameBytes {
            throw AgentNotifyError.payloadTooLarge(limit: maxFrameBytes, actual: data.count)
        }
        data.append(0x0A) // '\n'
        return data
    }

    /// Decode a UTF-8 JSON frame (with or without trailing newline).
    static func decode(_ data: Data) throws -> AgentNotifyRequest {
        let trimmed = data.last == 0x0A ? data.dropLast() : data
        if trimmed.count > maxFrameBytes {
            throw AgentNotifyError.payloadTooLarge(limit: maxFrameBytes, actual: trimmed.count)
        }
        do {
            return try JSONDecoder().decode(AgentNotifyRequest.self, from: trimmed)
        } catch {
            throw AgentNotifyError.decode(message: String(describing: error))
        }
    }
}

/// Resolves the Unix domain socket path the running app listens on.
///
/// Pinned to `~/Library/Application Support/Liney/agent-notify.sock` so it is
/// stable across launches and per-user. `sun_path` is limited to 104 bytes on
/// Darwin; a path under `Application Support` for any normal home directory
/// fits comfortably.
enum AgentNotifySocketPath {
    static let directoryName = "Liney"
    static let socketFileName = "agent-notify.sock"

    /// Override that lets tests pin the socket to a sandbox-friendly location.
    static var overrideURL: URL?

    static func resolveDirectory(
        fileManager: FileManager = .default,
        homeDirectory: String = NSHomeDirectory()
    ) -> URL {
        if let overrideURL {
            return overrideURL.deletingLastPathComponent()
        }
        let appSupport = URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
        return appSupport
    }

    static func resolveSocketURL(
        fileManager: FileManager = .default,
        homeDirectory: String = NSHomeDirectory()
    ) -> URL {
        if let overrideURL { return overrideURL }
        return resolveDirectory(fileManager: fileManager, homeDirectory: homeDirectory)
            .appendingPathComponent(socketFileName, isDirectory: false)
    }

    static func ensureDirectory(
        fileManager: FileManager = .default,
        homeDirectory: String = NSHomeDirectory()
    ) throws {
        let directory = resolveDirectory(fileManager: fileManager, homeDirectory: homeDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
