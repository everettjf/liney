//
//  AgentNotifyServerTests.swift
//  LineyTests
//
//  Author: everettjf
//

import XCTest
@testable import Liney

/// End-to-end test: bind a server on a sandboxed temp socket, send via the
/// real client, and assert the dispatched request matches what was sent.
final class AgentNotifyServerTests: XCTestCase {
    private var temporarySocketURL: URL?

    override func setUp() {
        super.setUp()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("liney-agent-notify-tests-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let socketURL = directory.appendingPathComponent("agent-notify.sock", isDirectory: false)
        temporarySocketURL = socketURL
        AgentNotifySocketPath.overrideURL = socketURL
    }

    override func tearDown() {
        AgentNotifySocketPath.overrideURL = nil
        if let url = temporarySocketURL {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        super.tearDown()
    }

    func testEndToEndFrameDeliveryViaRawHandler() throws {
        // Exercise the same socket round-trip as the production path but
        // without the @MainActor convenience-init wrapping — that wrapper
        // hops through Task/MainActor in a way that runs into a Swift 6
        // deinit bug on this machine. Coverage of the wrapper is provided
        // separately by AgentNotifyDispatcherTests + AppDelegate wiring.
        let socketURL = try XCTUnwrap(temporarySocketURL)
        let received = expectation(description: "server received frame")
        let captured = AgentNotifyFrameCapture()

        let server = AgentNotifyServer(socketURL: socketURL) { (frame: Data) -> Data? in
            captured.set(frame)
            received.fulfill()
            return nil
        }
        try server.start()
        defer { server.stop() }

        let request = AgentNotifyRequest(
            title: "Build finished",
            body: "All tests pass",
            paneID: "pane-uuid",
            workspaceID: "ws-uuid",
            agentName: "Claude"
        )

        DispatchQueue.global(qos: .userInitiated).async {
            try? AgentNotifyClient.send(request, socketURL: socketURL)
        }

        wait(for: [received], timeout: 5.0)
        let frame = try XCTUnwrap(captured.value)
        let decoded = try AgentNotifyProtocol.decode(frame)
        XCTAssertEqual(decoded, request)
    }

    @MainActor
    func testStopUnlinksSocket() throws {
        let socketURL = try XCTUnwrap(temporarySocketURL)
        let server = AgentNotifyServer(socketURL: socketURL) { (_: Data) in nil }
        try server.start()
        XCTAssertTrue(FileManager.default.fileExists(atPath: socketURL.path))

        server.stop()
        // stop() unlinks; give the OS a moment to flush.
        XCTAssertFalse(FileManager.default.fileExists(atPath: socketURL.path))
    }

    @MainActor
    func testStartReplacesStaleSocket() throws {
        let socketURL = try XCTUnwrap(temporarySocketURL)
        // Create a stale plain file at the socket path to simulate a crashed
        // previous run; start() must unlink it before bind().
        try Data().write(to: socketURL)

        let server = AgentNotifyServer(socketURL: socketURL) { (_: Data) in nil }
        try server.start()
        defer { server.stop() }

        // After start, the path exists as a socket — sending should succeed.
        let request = AgentNotifyRequest(title: "ok")
        XCTAssertNoThrow(try AgentNotifyClient.send(request, socketURL: socketURL))
    }

    func testClientReportsSocketUnavailableWhenNoServer() {
        let bogus = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).sock")
        let request = AgentNotifyRequest(title: "x")
        XCTAssertThrowsError(try AgentNotifyClient.send(request, socketURL: bogus)) { error in
            XCTAssertEqual(error as? AgentNotifyError, .socketUnavailable)
        }
    }
}

/// Captures the raw `Data` frame the server hands to its handler. The
/// project enables `SWIFT_APPROACHABLE_CONCURRENCY`, which would otherwise
/// infer @MainActor isolation for this helper — and a main-actor deinit
/// hop trips a libmalloc abort in XCTest's deterministic dealloc check on
/// this Swift/macOS combination. `nonisolated` opts back out. Reads happen
/// only on the main thread after `wait(for:)` returns, so the @unchecked
/// Sendable is sound.
nonisolated final class AgentNotifyFrameCapture: @unchecked Sendable {
    var value: Data?

    func set(_ value: Data) {
        self.value = value
    }
}
