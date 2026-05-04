//
//  LineyControlDispatcher.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

/// Decodes incoming control frames, performs auth, and routes the typed
/// request to a host. Returns the encoded JSON response (or `nil` for the
/// fire-and-forget `notify` case).
///
/// The dispatcher is host-agnostic so unit tests can drive it without an
/// `LineyDesktopApplication`. Production wires the host to the real
/// `LineyDesktopApplication` via `AppDelegate`.
@MainActor
protocol LineyControlHost: AnyObject {
    func handleNotify(_ request: AgentNotifyRequest)
    func handleOpen(_ request: LineyOpenRequest) -> LineyControlResponse
    func handleSplit(_ request: LineySplitRequest) -> LineyControlResponse
    func handleSendKeys(_ request: LineySendKeysRequest) -> LineyControlResponse
    func handleSessionList(_ request: LineySessionListRequest) -> LineyControlResponse
}

/// Note: this class is explicitly `nonisolated`. The project enables
/// `SWIFT_APPROACHABLE_CONCURRENCY`, which makes module-level types default
/// to `@MainActor`. Letting the dispatcher inherit that default emits a
/// main-actor deinit hop, which on this OS/Swift toolchain trips a libmalloc
/// abort under XCTest's deterministic dealloc check (XCTMemoryChecker).
/// `dispatch(frame:)` keeps `@MainActor` so the host call-sites remain safe.
nonisolated final class LineyControlDispatcher {
    weak var host: LineyControlHost?
    /// Token resolver — returns the user-configured trust token or nil if
    /// the URL-scheme feature is disabled. Indirection so tests can inject.
    var tokenResolver: () -> String?

    init(
        host: LineyControlHost?,
        tokenResolver: @escaping () -> String? = { MainActor.assumeIsolated { LineyURLScheme.isEnabled() ? LineyURLScheme.storedToken() : nil } }
    ) {
        self.host = host
        self.tokenResolver = tokenResolver
    }

    /// Decode + dispatch a single frame. Returns the response bytes (or nil
    /// for fire-and-forget commands like `notify`).
    @MainActor
    func dispatch(frame: Data) -> Data? {
        guard let envelope = try? JSONDecoder().decode(LineyControlEnvelope.self, from: trim(frame)) else {
            return LineyControlEncoder.encodeResponse(.failure("invalid-envelope"))
        }
        let cmd = envelope.cmd ?? .notify

        if cmd == .notify {
            // Notify is intentionally unauthenticated and produces no
            // response — any in-pane process can already print to stdout, so
            // emitting a notification is no privilege escalation.
            if let request = try? JSONDecoder().decode(AgentNotifyRequest.self, from: trim(frame)) {
                host?.handleNotify(request)
            }
            return nil
        }

        // All other commands require auth.
        guard let expected = tokenResolver(), !expected.isEmpty else {
            return LineyControlEncoder.encodeResponse(.failure("control-disabled"))
        }
        guard let provided = envelope.token, provided == expected else {
            return LineyControlEncoder.encodeResponse(.failure("token-mismatch"))
        }
        guard let host else {
            return LineyControlEncoder.encodeResponse(.failure("app-not-ready"))
        }

        let response: LineyControlResponse
        switch cmd {
        case .notify:
            // Already handled above.
            return nil
        case .open:
            guard let req = try? JSONDecoder().decode(LineyOpenRequest.self, from: trim(frame)) else {
                response = .failure("invalid-open-payload")
                break
            }
            response = host.handleOpen(req)
        case .split:
            let req = (try? JSONDecoder().decode(LineySplitRequest.self, from: trim(frame))) ?? LineySplitRequest()
            response = host.handleSplit(req)
        case .sendKeys:
            guard let req = try? JSONDecoder().decode(LineySendKeysRequest.self, from: trim(frame)) else {
                response = .failure("invalid-send-keys-payload")
                break
            }
            response = host.handleSendKeys(req)
        case .sessionList:
            let req = (try? JSONDecoder().decode(LineySessionListRequest.self, from: trim(frame))) ?? LineySessionListRequest()
            response = host.handleSessionList(req)
        }
        return LineyControlEncoder.encodeResponse(response)
    }

    private func trim(_ data: Data) -> Data {
        data.last == 0x0A ? data.dropLast() : data
    }
}
