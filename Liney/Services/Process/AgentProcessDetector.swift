//
//  AgentProcessDetector.swift
//  Liney
//
//  Author: everettjf
//

import Darwin
import Foundation

/// Best-effort detection of which AI coding agent (if any) is running inside a
/// pane's process tree, by classifying the executable path / argv of each
/// descendant process.
///
/// Liney's authoritative agent signal is the self-reported `liney status`
/// (see `AgentStatusStore`). This detector is the passive complement: it spots
/// an agent even when it never calls `liney status`, the way cmux / Prowl read
/// the terminal to populate their "active agents" view. We classify from
/// `KERN_PROCARGS2` argv rather than the 16-char `p_comm`, so node-wrapped
/// CLIs (Claude Code ships as `node .../claude-code/cli.js`) are still caught.
///
/// Matching is on *exact path components* of the executable and the first
/// script argument only — never arbitrary trailing args or the cwd — so a
/// repository that merely happens to contain "codex" in its path is not
/// misread as an agent.
enum AgentProcessDetector {

    struct Detected: Equatable {
        let pid: pid_t
        let type: String
        let displayName: String
    }

    struct Definition {
        let type: String
        let name: String
        /// Lower-cased tokens matched as an exact basename / path component.
        let tokens: [String]
    }

    /// Ordered most-specific first. Tokens are intentionally distinctive
    /// (package or binary names) to keep false positives near zero.
    static let definitions: [Definition] = [
        Definition(type: "claude-code", name: "Claude Code", tokens: ["claude", "claude-code"]),
        Definition(type: "codex", name: "Codex", tokens: ["codex", "codex-cli"]),
        Definition(type: "aider", name: "Aider", tokens: ["aider"]),
        Definition(type: "gemini", name: "Gemini CLI", tokens: ["gemini-cli", "gemini"]),
        Definition(type: "opencode", name: "OpenCode", tokens: ["opencode"]),
        Definition(type: "cursor-agent", name: "Cursor Agent", tokens: ["cursor-agent"]),
        Definition(type: "qwen-code", name: "Qwen Code", tokens: ["qwen-code", "qwen"]),
        Definition(type: "goose", name: "Goose", tokens: ["goose"]),
        Definition(type: "crush", name: "Crush", tokens: ["crush"]),
        Definition(type: "cline", name: "Cline", tokens: ["cline"]),
        Definition(type: "amp", name: "Amp", tokens: ["amp"]),
    ]

    // MARK: - Detection

    /// Walks `rootPID` and its descendants, returning the first detected agent
    /// (root first, then descendants breadth-first).
    static func detect(
        rootPID: pid_t,
        argsProvider: (pid_t) -> [UInt8]? = procArgsRaw(pid:)
    ) -> Detected? {
        var pids = [rootPID]
        pids.append(contentsOf: ProcessTree.descendants(of: rootPID))
        for pid in pids {
            guard let raw = argsProvider(pid),
                  let parsed = parseProcArgs(raw) else { continue }
            if let hit = classify(execPath: parsed.execPath, argv: parsed.argv) {
                return Detected(pid: pid, type: hit.type, displayName: hit.name)
            }
        }
        return nil
    }

    // MARK: - Pure classification (unit-tested)

    /// Classifies a process from its executable path and argv. Inspects the
    /// executable basename/components and the first script argument
    /// (`argv[1]`, where node/python wrappers carry the agent package path).
    static func classify(execPath: String, argv: [String]) -> (type: String, name: String)? {
        var candidates = Set<String>()
        addComponents(of: execPath, to: &candidates)
        if let first = argv.first { addComponents(of: first, to: &candidates) }
        if argv.count >= 2 { addComponents(of: argv[1], to: &candidates) }

        for def in definitions {
            for token in def.tokens where candidates.contains(token) {
                return (def.type, def.name)
            }
        }
        return nil
    }

    private static func addComponents(of path: String, to set: inout Set<String>) {
        let lower = path.lowercased()
        set.insert((lower as NSString).lastPathComponent)
        for component in lower.split(separator: "/") where !component.isEmpty {
            set.insert(String(component))
        }
    }

    // MARK: - KERN_PROCARGS2 parsing (unit-tested)

    /// Parses a `KERN_PROCARGS2` buffer into the executable path and argv.
    /// Layout: `int argc`, NUL-terminated exec_path, alignment NULs, then
    /// `argc` NUL-terminated argument strings, then the environment.
    static func parseProcArgs(_ data: [UInt8]) -> (execPath: String, argv: [String])? {
        guard data.count > 4 else { return nil }
        let argc = data.prefix(4).withUnsafeBytes { $0.load(as: Int32.self) }
        guard argc >= 0 else { return nil }

        var i = 4
        let execStart = i
        while i < data.count, data[i] != 0 { i += 1 }
        let execPath = String(decoding: data[execStart..<i], as: UTF8.self)
        while i < data.count, data[i] == 0 { i += 1 } // skip padding NULs

        var argv: [String] = []
        var read = 0
        while read < Int(argc), i < data.count {
            let start = i
            while i < data.count, data[i] != 0 { i += 1 }
            argv.append(String(decoding: data[start..<i], as: UTF8.self))
            while i < data.count, data[i] == 0 { i += 1 }
            read += 1
        }
        return (execPath, argv)
    }

    // MARK: - sysctl reader

    /// Reads the raw `KERN_PROCARGS2` buffer for `pid`, or nil if unavailable
    /// (process gone, or not owned by the current user).
    static func procArgsRaw(pid: pid_t) -> [UInt8]? {
        var argmax: Int = 0
        var argmaxSize = MemoryLayout<Int>.size
        var argmaxMib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&argmaxMib, 2, &argmax, &argmaxSize, nil, 0) == 0, argmax > 0 else {
            return nil
        }

        var buffer = [UInt8](repeating: 0, count: argmax)
        var size = argmax
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return Array(buffer.prefix(size))
    }
}
