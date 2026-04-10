//
//  TmuxTitleDetector.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

/// Pure static detection logic for identifying tmux sessions from terminal title strings.
enum TmuxTitleDetector {

    /// Returns detected tmux session name, or nil if no tmux detected.
    ///
    /// Three detection patterns:
    /// 1. `[session-name] ...` — tmux status bar format
    /// 2. `tmux ...` — preexec command title
    /// 3. `session:index:program - "title"` — tmux set-titles format
    static func detectSession(fromTitle title: String) -> String? {
        guard !title.isEmpty else { return nil }

        let lower = title.lowercased()

        // Pattern 1: tmux status bar format "[session-name] ..."
        if lower.hasPrefix("[") {
            if let closeBracket = title.firstIndex(of: "]") {
                let sessionName = String(title[title.index(after: title.startIndex)..<closeBracket])
                if !sessionName.isEmpty {
                    return sessionName
                }
            }
        }

        // Pattern 2: preexec title showing the tmux command being run
        // e.g. "tmux", "tmux new -s hello", "tmux attach -t mysession"
        if lower.hasPrefix("tmux") {
            let args = title.split(separator: " ").map(String.init)
            if args.first?.lowercased() == "tmux" {
                if let sessionName = parseTmuxSessionName(from: Array(args.dropFirst())) {
                    return sessionName
                } else {
                    // Bare "tmux" or unrecognized args — return placeholder.
                    return "tmux"
                }
            }
        }

        // Pattern 3: tmux set-titles format "#S:#I:#W - \"#T\""
        // e.g. "13:0:bash - \"hostname\"", "dev:1:vim - \"file.txt\""
        let parts = title.split(separator: ":", maxSplits: 2).map(String.init)
        if parts.count == 3,
           let _ = Int(parts[1]),
           parts[2].contains(" - ") {
            let sessionName = parts[0]
            if !sessionName.isEmpty {
                return sessionName
            }
        }

        return nil
    }

    /// Parses session name from tmux subcommand arguments.
    /// Handles: new -s <name>, new-session -s <name>, attach -t <name>,
    /// attach-session -t <name>, a -t <name>
    static func parseTmuxSessionName(from args: [String]) -> String? {
        var i = 0
        while i < args.count {
            let arg = args[i]
            // -s flag: session name for new/new-session
            if arg == "-s", i + 1 < args.count {
                return args[i + 1]
            }
            // -t flag: target session for attach/attach-session
            if arg == "-t", i + 1 < args.count {
                // Target may contain "session:window.pane", extract just session
                let target = args[i + 1]
                if let colonIdx = target.firstIndex(of: ":") {
                    return String(target[target.startIndex..<colonIdx])
                }
                return target
            }
            i += 1
        }
        return nil
    }
}
