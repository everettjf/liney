//
//  AgentResumeRegistryTests.swift
//  LineyTests
//
//  Author: everettjf
//

import XCTest
@testable import Liney

final class AgentResumeRegistryTests: XCTestCase {
    func testClaudeViaEnvGetsContinue() {
        let result = AgentResumeRegistry.resumedArguments(
            executablePath: "/usr/bin/env",
            arguments: ["claude"]
        )
        XCTAssertEqual(result, ["claude", "--continue"])
    }

    func testClaudeDirectExecutableGetsContinue() {
        let result = AgentResumeRegistry.resumedArguments(
            executablePath: "/opt/homebrew/bin/claude",
            arguments: []
        )
        XCTAssertEqual(result, ["--continue"])
    }

    func testClaudeKeepsExistingFlagsAndAppendsContinue() {
        let result = AgentResumeRegistry.resumedArguments(
            executablePath: "/usr/bin/env",
            arguments: ["claude", "--model", "opus"]
        )
        XCTAssertEqual(result, ["claude", "--model", "opus", "--continue"])
    }

    func testClaudeAlreadyResumingIsLeftAlone() {
        XCTAssertNil(AgentResumeRegistry.resumedArguments(
            executablePath: "/usr/bin/env", arguments: ["claude", "--continue"]
        ))
        XCTAssertNil(AgentResumeRegistry.resumedArguments(
            executablePath: "/usr/bin/env", arguments: ["claude", "-c"]
        ))
        XCTAssertNil(AgentResumeRegistry.resumedArguments(
            executablePath: "/usr/bin/env", arguments: ["claude", "--resume"]
        ))
    }

    func testEnvAssignmentsAreSkippedToFindAgent() {
        let result = AgentResumeRegistry.resumedArguments(
            executablePath: "/usr/bin/env",
            arguments: ["FOO=bar", "claude"]
        )
        XCTAssertEqual(result, ["FOO=bar", "claude", "--continue"])
    }

    func testBareCodexGetsResumeLast() {
        let result = AgentResumeRegistry.resumedArguments(
            executablePath: "/usr/bin/env",
            arguments: ["codex"]
        )
        XCTAssertEqual(result, ["codex", "resume", "--last"])
    }

    func testCodexWithSubcommandIsLeftAlone() {
        // Don't reinterpret an explicit codex subcommand/args.
        XCTAssertNil(AgentResumeRegistry.resumedArguments(
            executablePath: "/usr/bin/env", arguments: ["codex", "exec", "do thing"]
        ))
    }

    func testAiderGetsRestoreChatHistory() {
        let result = AgentResumeRegistry.resumedArguments(
            executablePath: "/usr/bin/env",
            arguments: ["aider", "--sonnet"]
        )
        XCTAssertEqual(result, ["aider", "--sonnet", "--restore-chat-history"])
    }

    func testAiderAlreadyRestoringIsLeftAlone() {
        XCTAssertNil(AgentResumeRegistry.resumedArguments(
            executablePath: "/usr/bin/env", arguments: ["aider", "--restore-chat-history"]
        ))
    }

    func testUnknownAgentIsLeftAlone() {
        XCTAssertNil(AgentResumeRegistry.resumedArguments(
            executablePath: "/bin/zsh", arguments: ["-l"]
        ))
        XCTAssertNil(AgentResumeRegistry.resumedArguments(
            executablePath: "/usr/bin/env", arguments: ["gemini"]
        ))
    }
}

final class PaneSnapshotResumeFlagTests: XCTestCase {
    private func agentSnapshot() -> PaneSnapshot {
        PaneSnapshot(
            id: UUID(),
            preferredWorkingDirectory: "/repo",
            preferredEngine: .libghosttyPreferred,
            backendConfiguration: .agent(
                AgentSessionConfiguration(
                    name: "Claude Code",
                    launchPath: "/usr/bin/env",
                    arguments: ["claude"],
                    environment: [:],
                    workingDirectory: nil
                )
            )
        )
    }

    func testFreshSnapshotIsNotRestored() {
        XCTAssertFalse(agentSnapshot().restoredFromDisk)
    }

    func testDecodedSnapshotIsMarkedRestored() throws {
        let encoded = try JSONEncoder().encode(agentSnapshot())
        let decoded = try JSONDecoder().decode(PaneSnapshot.self, from: encoded)
        XCTAssertTrue(decoded.restoredFromDisk, "a snapshot loaded from disk is a restore")
    }

    func testRestoredFlagIsNotPersisted() throws {
        // Even if a snapshot is marked restored in memory, encoding must not
        // carry the flag (it is purely transient).
        var snapshot = agentSnapshot()
        snapshot.restoredFromDisk = true
        let json = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        XCTAssertFalse(json.contains("restoredFromDisk"))
    }

    func testEqualityAndHashIgnoreRestoredFlag() {
        var a = agentSnapshot()
        var b = a
        a.restoredFromDisk = true
        b.restoredFromDisk = false
        XCTAssertEqual(a, b, "origin must not affect snapshot identity")
        XCTAssertEqual(a.hashValue, b.hashValue)
    }
}
