//
//  AgentProcessDetectorTests.swift
//  LineyTests
//
//  Author: everettjf
//

import XCTest
@testable import Liney

final class AgentProcessDetectorClassifyTests: XCTestCase {
    func testNativeBinaryMatchesByBasename() {
        let hit = AgentProcessDetector.classify(
            execPath: "/opt/homebrew/bin/codex",
            argv: ["codex", "--model", "gpt-5.5"]
        )
        XCTAssertEqual(hit?.type, "codex")
        XCTAssertEqual(hit?.name, "Codex")
    }

    func testNodeWrappedClaudeMatchesByPackagePathComponent() {
        // Claude Code ships as `node .../@anthropic-ai/claude-code/cli.js`.
        let hit = AgentProcessDetector.classify(
            execPath: "/usr/local/bin/node",
            argv: ["node", "/usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js"]
        )
        XCTAssertEqual(hit?.type, "claude-code")
    }

    func testAiderMatches() {
        let hit = AgentProcessDetector.classify(
            execPath: "/Users/x/.local/bin/aider",
            argv: ["aider", "--sonnet"]
        )
        XCTAssertEqual(hit?.type, "aider")
    }

    func testPlainShellIsNotAnAgent() {
        XCTAssertNil(AgentProcessDetector.classify(execPath: "/bin/zsh", argv: ["-zsh"]))
    }

    func testCwdContainingAgentNameDoesNotFalseMatch() {
        // A user editing under ~/dev/codex-notes must not register as Codex:
        // we only inspect the executable and the first script arg, not later
        // file arguments.
        let hit = AgentProcessDetector.classify(
            execPath: "/bin/cat",
            argv: ["cat", "/Users/x/dev/codex-notes/todo.md"]
        )
        // argv[1] path component "codex-notes" != token "codex", so no match.
        XCTAssertNil(hit)
    }
}

final class AgentProcArgsParseTests: XCTestCase {
    /// Builds a synthetic KERN_PROCARGS2 buffer: argc, exec_path, NUL padding,
    /// then argc argv strings, then a trailing env entry.
    private func makeBuffer(argc: Int32, execPath: String, argv: [String], env: [String]) -> [UInt8] {
        var bytes: [UInt8] = []
        withUnsafeBytes(of: argc) { bytes.append(contentsOf: $0) }
        bytes.append(contentsOf: Array(execPath.utf8)); bytes.append(0)
        bytes.append(0); bytes.append(0) // alignment padding NULs
        for arg in argv { bytes.append(contentsOf: Array(arg.utf8)); bytes.append(0) }
        for entry in env { bytes.append(contentsOf: Array(entry.utf8)); bytes.append(0) }
        return bytes
    }

    func testParsesExecPathAndArgv() {
        let buffer = makeBuffer(
            argc: 2,
            execPath: "/usr/local/bin/node",
            argv: ["node", "/path/to/claude-code/cli.js"],
            env: ["PATH=/usr/bin"]
        )
        let parsed = AgentProcessDetector.parseProcArgs(buffer)
        XCTAssertEqual(parsed?.execPath, "/usr/local/bin/node")
        XCTAssertEqual(parsed?.argv, ["node", "/path/to/claude-code/cli.js"])
    }

    func testParseStopsAtArgcAndIgnoresEnv() {
        let buffer = makeBuffer(
            argc: 1,
            execPath: "/bin/zsh",
            argv: ["-zsh"],
            env: ["HOME=/Users/x", "TERM=xterm"]
        )
        let parsed = AgentProcessDetector.parseProcArgs(buffer)
        XCTAssertEqual(parsed?.argv, ["-zsh"], "env entries must not leak into argv")
    }

    func testEndToEndDetectViaInjectedArgs() {
        // detect() with an injected args provider — no real process needed.
        let buffer = makeBuffer(
            argc: 1,
            execPath: "/opt/homebrew/bin/codex",
            argv: ["codex"],
            env: []
        )
        let detected = AgentProcessDetector.detect(rootPID: 4242) { pid in
            pid == 4242 ? buffer : nil
        }
        XCTAssertEqual(detected?.type, "codex")
        XCTAssertEqual(detected?.pid, 4242)
    }

    func testTooShortBufferReturnsNil() {
        XCTAssertNil(AgentProcessDetector.parseProcArgs([0, 1]))
    }
}
