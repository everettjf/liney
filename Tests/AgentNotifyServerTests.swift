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

    @MainActor
    func testEndToEndDeliveryPreservesAllFields() throws {
        let socketURL = try XCTUnwrap(temporarySocketURL)
        let received = expectation(description: "server received request")
        var captured: AgentNotifyRequest?

        let server = AgentNotifyServer(socketURL: socketURL) { request in
            captured = request
            received.fulfill()
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

        // Send on a background queue so the main-actor handler can drain.
        DispatchQueue.global(qos: .userInitiated).async {
            try? AgentNotifyClient.send(request, socketURL: socketURL)
        }

        wait(for: [received], timeout: 5.0)
        XCTAssertEqual(captured, request)
    }

    @MainActor
    func testStopUnlinksSocket() throws {
        let socketURL = try XCTUnwrap(temporarySocketURL)
        let server = AgentNotifyServer(socketURL: socketURL) { _ in }
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

        let server = AgentNotifyServer(socketURL: socketURL) { _ in }
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
