//
//  AgentResumeRegistry.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

/// Knows how to turn an agent pane's launch command into one that resumes the
/// agent's most recent conversation for the working directory, so a pane
/// restored after relaunch re-attaches to its session instead of starting cold.
///
/// Conservative by design: only agents with a verified, non-interactive resume
/// flag are transformed, the transform is idempotent (won't double-add), and an
/// unrecognized or already-resuming command is left exactly as-is.
///
/// Verified resume conventions (all scope to the current directory):
///   - claude  → `--continue`            (most recent conversation in cwd)
///   - codex   → `resume --last`         (most recent session in cwd)
///   - aider   → `--restore-chat-history`
enum AgentResumeRegistry {

    /// Returns launch arguments adjusted to resume the agent, or nil to leave
    /// the launch untouched (unknown agent, or it already resumes).
    ///
    /// Handles the common `/usr/bin/env <agent> …` wrapper: the agent token is
    /// the first non-`KEY=VALUE` argument; otherwise the executable itself is
    /// the agent.
    static func resumedArguments(executablePath: String, arguments: [String]) -> [String]? {
        let executableBase = (executablePath as NSString).lastPathComponent.lowercased()

        let agentToken: String
        let agentTokenIndex: Int  // index in `arguments`, or -1 if the executable is the agent

        if executableBase == "env" {
            guard let index = arguments.firstIndex(where: { !$0.contains("=") }) else {
                return nil  // only env assignments, no command
            }
            agentToken = (arguments[index] as NSString).lastPathComponent.lowercased()
            agentTokenIndex = index
        } else {
            agentToken = executableBase
            agentTokenIndex = -1
        }

        // The agent's own arguments are everything after the agent token.
        let ownArguments = agentTokenIndex >= 0
            ? Array(arguments[(agentTokenIndex + 1)...])
            : arguments

        guard let rule = rule(for: agentToken),
              let resumedOwn = rule(ownArguments) else {
            return nil
        }

        if agentTokenIndex >= 0 {
            return Array(arguments[0...agentTokenIndex]) + resumedOwn
        }
        return resumedOwn
    }

    /// Maps an agent token to a transform over its own arguments. The transform
    /// returns nil when the launch should be left alone.
    private static func rule(for token: String) -> (([String]) -> [String]?)? {
        switch token {
        case "claude":
            return { args in
                let resumeFlags: Set<String> = ["--continue", "-c", "--resume", "-r"]
                guard !args.contains(where: { resumeFlags.contains($0) }) else { return nil }
                return args + ["--continue"]
            }
        case "codex":
            return { args in
                // Only a bare `codex` is safe to rewrite: any args may already
                // be a subcommand (`exec`, `resume`, …) or carry flag values we
                // must not reinterpret.
                args.isEmpty ? ["resume", "--last"] : nil
            }
        case "aider":
            return { args in
                guard !args.contains("--restore-chat-history") else { return nil }
                return args + ["--restore-chat-history"]
            }
        default:
            return nil
        }
    }
}
