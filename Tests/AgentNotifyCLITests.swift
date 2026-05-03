//
//  AgentNotifyCLITests.swift
//  LineyTests
//
//  Author: everettjf
//

import XCTest
@testable import Liney

final class AgentNotifyCLITests: XCTestCase {
    func testParsePositionalTitleAndBody() throws {
        let options = try AgentNotifyCLI.parse(arguments: ["Build done", "All tests pass"])
        XCTAssertEqual(options.title, "Build done")
        XCTAssertEqual(options.body, "All tests pass")
    }

    func testParseLongFlags() throws {
        let options = try AgentNotifyCLI.parse(arguments: [
            "--title", "Claude waiting",
            "--body", "needs your input",
            "--pane", "ABC",
            "--workspace", "WSX",
            "--agent", "Claude",
        ])
        XCTAssertEqual(options.title, "Claude waiting")
        XCTAssertEqual(options.body, "needs your input")
        XCTAssertEqual(options.paneID, "ABC")
        XCTAssertEqual(options.workspaceID, "WSX")
        XCTAssertEqual(options.agentName, "Claude")
    }

    func testParseShortFlags() throws {
        let options = try AgentNotifyCLI.parse(arguments: [
            "-t", "Title",
            "-m", "Body",
            "-p", "PANE",
            "-a", "Codex",
        ])
        XCTAssertEqual(options.title, "Title")
        XCTAssertEqual(options.body, "Body")
        XCTAssertEqual(options.paneID, "PANE")
        XCTAssertEqual(options.agentName, "Codex")
    }

    func testParseHelpAndVersion() throws {
        XCTAssertTrue(try AgentNotifyCLI.parse(arguments: ["--help"]).showHelp)
        XCTAssertTrue(try AgentNotifyCLI.parse(arguments: ["-h"]).showHelp)
        XCTAssertTrue(try AgentNotifyCLI.parse(arguments: ["--version"]).showVersion)
        XCTAssertTrue(try AgentNotifyCLI.parse(arguments: ["-V"]).showVersion)
    }

    func testParseRejectsUnknownFlag() {
        XCTAssertThrowsError(try AgentNotifyCLI.parse(arguments: ["--bogus"])) { error in
            XCTAssertEqual(error as? AgentNotifyCLI.ParseError, .unknownFlag("--bogus"))
        }
    }

    func testParseRejectsFlagWithoutValue() {
        XCTAssertThrowsError(try AgentNotifyCLI.parse(arguments: ["--title"])) { error in
            XCTAssertEqual(error as? AgentNotifyCLI.ParseError, .missingValue(flag: "--title"))
        }
    }

    func testMakeRequestPullsPaneIDFromEnvironmentWhenAbsent() throws {
        let options = try AgentNotifyCLI.parse(arguments: ["--title", "Done"])
        let request = try AgentNotifyCLI.makeRequest(
            from: options,
            environment: ["LINEY_PANE_ID": "env-pane-id"]
        )
        XCTAssertEqual(request.paneID, "env-pane-id")
    }

    func testMakeRequestPrefersExplicitPaneIDOverEnvironment() throws {
        let options = try AgentNotifyCLI.parse(arguments: ["--title", "T", "--pane", "explicit"])
        let request = try AgentNotifyCLI.makeRequest(
            from: options,
            environment: ["LINEY_PANE_ID": "env-pane-id"]
        )
        XCTAssertEqual(request.paneID, "explicit")
    }

    func testMakeRequestRejectsMissingTitleAndBody() {
        let options = AgentNotifyCLI.Options()
        XCTAssertThrowsError(try AgentNotifyCLI.makeRequest(from: options, environment: [:])) { error in
            XCTAssertEqual(error as? AgentNotifyCLI.ParseError, .missingTitleAndBody)
        }
    }

    func testRunReturnsOKOnSuccess() {
        var captured: AgentNotifyRequest?
        var stderrOutput = ""
        let exit = AgentNotifyCLI.run(
            arguments: ["Build done"],
            send: { captured = $0 },
            stdoutWriter: { _ in },
            stderrWriter: { stderrOutput += $0 },
            environment: [:]
        )
        XCTAssertEqual(exit, .ok)
        XCTAssertEqual(captured?.title, "Build done")
        XCTAssertTrue(stderrOutput.isEmpty, "stderr should be empty on success, got: \(stderrOutput)")
    }

    func testRunReturnsUnavailableWhenServerMissing() {
        let exit = AgentNotifyCLI.run(
            arguments: ["Build done"],
            send: { _ in throw AgentNotifyError.socketUnavailable },
            stdoutWriter: { _ in },
            stderrWriter: { _ in },
            environment: [:]
        )
        XCTAssertEqual(exit, .unavailable)
    }

    func testRunReturnsUsageOnMissingTitleAndBody() {
        let exit = AgentNotifyCLI.run(
            arguments: [],
            send: { _ in XCTFail("send should not be called") },
            stdoutWriter: { _ in },
            stderrWriter: { _ in },
            environment: [:]
        )
        XCTAssertEqual(exit, .usage)
    }

    func testRunReturnsOKOnHelp() {
        var stdoutOutput = ""
        let exit = AgentNotifyCLI.run(
            arguments: ["--help"],
            send: { _ in XCTFail("send should not be called") },
            stdoutWriter: { stdoutOutput += $0 },
            stderrWriter: { _ in },
            environment: [:]
        )
        XCTAssertEqual(exit, .ok)
        XCTAssertTrue(stdoutOutput.contains("liney notify"))
    }
}
