//
//  LineyControlCLITests.swift
//  LineyTests
//
//  Author: everettjf
//

import XCTest
@testable import Liney

/// Drives the CLI argument parsers with stubbed I/O so we can assert exit
/// codes and the exact bytes that would have been written to the socket
/// without standing up a real server.
final class LineyControlCLITests: XCTestCase {

    // MARK: - open

    func testOpenRequiresRepoPositional() {
        let stderr = StreamCollector()
        let exit = LineyControlCLI.runOpen(
            arguments: [],
            send: { _ in nil },
            environment: ["LINEY_CONTROL_TOKEN": "t"],
            stdoutWriter: { _ in },
            stderrWriter: stderr.write
        )
        XCTAssertEqual(exit, .usage)
    }

    func testOpenRequiresToken() {
        let stderr = StreamCollector()
        let exit = LineyControlCLI.runOpen(
            arguments: ["/repo"],
            send: { _ in nil },
            environment: [:],
            stdoutWriter: { _ in },
            stderrWriter: stderr.write
        )
        XCTAssertEqual(exit, .authRequired)
        XCTAssertTrue(stderr.text.contains("--token"))
    }

    func testOpenEncodesFrameWithRepoAndWorktree() throws {
        let captured = FrameCollector()
        let exit = LineyControlCLI.runOpen(
            arguments: ["/repo", "--worktree", "/repo/wt"],
            send: captured.capture,
            environment: ["LINEY_CONTROL_TOKEN": "secret"],
            stdoutWriter: { _ in },
            stderrWriter: { _ in }
        )
        XCTAssertEqual(exit, .ok)
        let json = try captured.decodedJSON()
        XCTAssertEqual(json["cmd"] as? String, "open")
        XCTAssertEqual(json["token"] as? String, "secret")
        XCTAssertEqual(json["repo"] as? String, "/repo")
        XCTAssertEqual(json["worktree"] as? String, "/repo/wt")
    }

    func testOpenSurfacesServerErrorAsIOFailure() {
        let stderr = StreamCollector()
        let exit = LineyControlCLI.runOpen(
            arguments: ["/repo"],
            send: { _ in LineyControlResponse.failure("boom") },
            environment: ["LINEY_CONTROL_TOKEN": "secret"],
            stdoutWriter: { _ in },
            stderrWriter: stderr.write
        )
        XCTAssertEqual(exit, .ioError)
        XCTAssertTrue(stderr.text.contains("boom"))
    }

    func testOpenMapsTokenMismatchToAuthExitCode() {
        let stderr = StreamCollector()
        let exit = LineyControlCLI.runOpen(
            arguments: ["/repo"],
            send: { _ in LineyControlResponse.failure("token-mismatch") },
            environment: ["LINEY_CONTROL_TOKEN": "secret"],
            stdoutWriter: { _ in },
            stderrWriter: stderr.write
        )
        XCTAssertEqual(exit, .authRequired)
    }

    func testOpenReportsUnavailableWhenSocketDown() {
        let stderr = StreamCollector()
        let exit = LineyControlCLI.runOpen(
            arguments: ["/repo"],
            send: { _ in throw AgentNotifyError.socketUnavailable },
            environment: ["LINEY_CONTROL_TOKEN": "secret"],
            stdoutWriter: { _ in },
            stderrWriter: stderr.write
        )
        XCTAssertEqual(exit, .unavailable)
        XCTAssertTrue(stderr.text.contains("not running"))
    }

    // MARK: - split

    func testSplitDefaultsAndFallsBackToEnvPane() throws {
        let captured = FrameCollector()
        _ = LineyControlCLI.runSplit(
            arguments: [],
            send: captured.capture,
            environment: [
                "LINEY_CONTROL_TOKEN": "secret",
                LineyAgentNotifyEnvironment.paneIDKey: "pane-from-env",
            ],
            stdoutWriter: { _ in },
            stderrWriter: { _ in }
        )
        let json = try captured.decodedJSON()
        XCTAssertEqual(json["cmd"] as? String, "split")
        XCTAssertEqual(json["pane"] as? String, "pane-from-env")
        // axis omitted when not provided — server defaults to vertical
        XCTAssertNil(json["axis"])
    }

    func testSplitHorizontalAxisIsForwarded() throws {
        let captured = FrameCollector()
        _ = LineyControlCLI.runSplit(
            arguments: ["--axis", "horizontal"],
            send: captured.capture,
            environment: ["LINEY_CONTROL_TOKEN": "secret"],
            stdoutWriter: { _ in },
            stderrWriter: { _ in }
        )
        let json = try captured.decodedJSON()
        XCTAssertEqual(json["axis"] as? String, "horizontal")
    }

    // MARK: - send-keys

    func testSendKeysAcceptsPositionalPaneAndText() throws {
        let captured = FrameCollector()
        let exit = LineyControlCLI.runSendKeys(
            arguments: ["pane-uuid", "ls -la\n"],
            send: captured.capture,
            environment: ["LINEY_CONTROL_TOKEN": "secret"],
            stdoutWriter: { _ in },
            stderrWriter: { _ in }
        )
        XCTAssertEqual(exit, .ok)
        let json = try captured.decodedJSON()
        XCTAssertEqual(json["pane"] as? String, "pane-uuid")
        XCTAssertEqual(json["text"] as? String, "ls -la\n")
    }

    func testSendKeysFlagFormBeatsPositionalAbsence() throws {
        let captured = FrameCollector()
        let exit = LineyControlCLI.runSendKeys(
            arguments: ["--pane", "p1", "--text", "y"],
            send: captured.capture,
            environment: ["LINEY_CONTROL_TOKEN": "secret"],
            stdoutWriter: { _ in },
            stderrWriter: { _ in }
        )
        XCTAssertEqual(exit, .ok)
        let json = try captured.decodedJSON()
        XCTAssertEqual(json["pane"] as? String, "p1")
        XCTAssertEqual(json["text"] as? String, "y")
    }

    func testSendKeysRequiresPane() {
        let stderr = StreamCollector()
        let exit = LineyControlCLI.runSendKeys(
            arguments: ["--text", "hi"],
            send: { _ in nil },
            environment: ["LINEY_CONTROL_TOKEN": "secret"],
            stdoutWriter: { _ in },
            stderrWriter: stderr.write
        )
        XCTAssertEqual(exit, .usage)
        XCTAssertTrue(stderr.text.contains("pane is required"))
    }

    func testSendKeysRequiresText() {
        let stderr = StreamCollector()
        let exit = LineyControlCLI.runSendKeys(
            arguments: ["--pane", "p1"],
            send: { _ in nil },
            environment: ["LINEY_CONTROL_TOKEN": "secret"],
            stdoutWriter: { _ in },
            stderrWriter: stderr.write
        )
        XCTAssertEqual(exit, .usage)
        XCTAssertTrue(stderr.text.contains("text is required"))
    }

    // MARK: - session list

    func testSessionListRequiresToken() {
        let stderr = StreamCollector()
        let exit = LineyControlCLI.runSessionList(
            arguments: [],
            send: { _ in nil },
            environment: [:],
            stdoutWriter: { _ in },
            stderrWriter: stderr.write
        )
        XCTAssertEqual(exit, .authRequired)
    }

    func testSessionListPrintsHumanLines() {
        let stdout = StreamCollector()
        let exit = LineyControlCLI.runSessionList(
            arguments: [],
            send: { _ in
                LineyControlResponse(
                    ok: true,
                    error: nil,
                    sessions: [
                        LineyControlSession(
                            workspaceID: "w1",
                            workspaceName: "demo",
                            paneID: "p-1",
                            cwd: "/tmp/x",
                            branch: "main",
                            listeningPorts: [3000, 8080]
                        )
                    ]
                )
            },
            environment: ["LINEY_CONTROL_TOKEN": "secret"],
            stdoutWriter: stdout.write,
            stderrWriter: { _ in }
        )
        XCTAssertEqual(exit, .ok)
        XCTAssertTrue(stdout.text.contains("demo [main] p-1 /tmp/x ports=:3000,:8080"))
    }

    func testSessionListJSONShape() throws {
        let stdout = StreamCollector()
        let exit = LineyControlCLI.runSessionList(
            arguments: ["--json"],
            send: { _ in
                LineyControlResponse(
                    ok: true,
                    error: nil,
                    sessions: [
                        LineyControlSession(
                            workspaceID: "w1",
                            workspaceName: "demo",
                            paneID: "p-1",
                            cwd: "/tmp/x",
                            branch: nil,
                            listeningPorts: []
                        )
                    ]
                )
            },
            environment: ["LINEY_CONTROL_TOKEN": "secret"],
            stdoutWriter: stdout.write,
            stderrWriter: { _ in }
        )
        XCTAssertEqual(exit, .ok)
        let data = Data(stdout.text.utf8)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        XCTAssertEqual(parsed?.first?["workspace"] as? String, "w1")
        XCTAssertEqual(parsed?.first?["pane"] as? String, "p-1")
    }

    // MARK: - encodeFrame helper

    func testEncodeFrameOmitsNilPayloadEntries() throws {
        let frame = LineyControlCLI.encodeFrame(
            cmd: "split",
            token: "t",
            payload: ["pane": nil as Any?, "axis": "vertical"]
        )
        let trimmed = frame.last == 0x0A ? frame.dropLast() : frame
        let json = try JSONSerialization.jsonObject(with: trimmed) as? [String: Any]
        XCTAssertEqual(json?["cmd"] as? String, "split")
        XCTAssertEqual(json?["axis"] as? String, "vertical")
        XCTAssertEqual(json?["v"] as? Int, 1)
        XCTAssertNil(json?["pane"])
    }

    func testEncodeFrameTerminatesWithNewline() {
        let frame = LineyControlCLI.encodeFrame(cmd: "notify", token: nil, payload: [:])
        XCTAssertEqual(frame.last, 0x0A)
    }
}

// MARK: - Test fixtures

// `nonisolated` opt-out: the project sets SWIFT_APPROACHABLE_CONCURRENCY,
// which would otherwise infer @MainActor isolation for these helpers. A
// main-actor deinit hop trips a libmalloc abort in XCTest's deterministic
// dealloc check on this Swift/macOS combo, so we keep these strictly
// nonisolated. Reads only happen on the calling test's thread.
nonisolated private final class StreamCollector {
    private(set) var text: String = ""
    func write(_ line: String) { text += line + "\n" }
}

nonisolated private final class FrameCollector {
    private(set) var frame: Data?

    func capture(_ data: Data) throws -> LineyControlResponse? {
        frame = data
        return .success
    }

    func decodedJSON() throws -> [String: Any] {
        guard let raw = frame else {
            throw NSError(domain: "FrameCollector", code: -1, userInfo: [NSLocalizedDescriptionKey: "no frame captured"])
        }
        let trimmed = raw.last == 0x0A ? raw.dropLast() : raw
        guard let object = try JSONSerialization.jsonObject(with: trimmed) as? [String: Any] else {
            throw NSError(domain: "FrameCollector", code: -2, userInfo: [NSLocalizedDescriptionKey: "frame was not a JSON object"])
        }
        return object
    }
}
