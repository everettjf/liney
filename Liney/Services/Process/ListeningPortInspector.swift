//
//  ListeningPortInspector.swift
//  Liney
//
//  Author: everettjf
//

import Darwin
import Foundation

/// Discovers which TCP ports a pane (and its descendant processes) is
/// listening on, so the sidebar can show "this pane is hosting :3000".
///
/// Implementation: shell out to `lsof -aPn -iTCP -sTCP:LISTEN -p <pid>...`.
/// `lsof` is preinstalled on macOS, supports the multi-PID `-p` form so we
/// only spawn once per refresh, and gives a stable parseable text format.
///
/// We avoid the `proc_pidfdinfo` SPI for now — it requires entitlements that
/// would broaden Liney's signing surface, and a single `lsof` shell-out is
/// cheap because we cap the refresh rate.
enum ListeningPortInspector {

    /// Result of inspecting a process tree's listening sockets.
    struct Result: Equatable {
        var ports: [Int]
        /// Distinct executable basenames that hold a listening socket. Useful
        /// for sidebar tooltips ("vite, node :3000").
        var processNames: [String]
    }

    /// Returns the listening TCP ports for the given root PID and all of its
    /// descendants. Returns an empty result if the process tree has no
    /// listeners or if `lsof` could not be invoked.
    static func inspect(rootPID: pid_t) async -> Result {
        let descendants = ProcessTree.descendants(of: rootPID)
        var pids = Array(descendants)
        pids.append(rootPID)
        if pids.isEmpty { return Result(ports: [], processNames: []) }
        return await inspect(pids: pids, runner: ShellCommandRunner())
    }

    /// Test seam: parse-only entry.
    static func parse(_ lsofOutput: String) -> Result {
        var ports = Set<Int>()
        var names = Set<String>()
        for line in lsofOutput.split(whereSeparator: \.isNewline) {
            // `lsof -P -n -F` field-mode output is harder to parse than the
            // default tabular form; the default looks like:
            //   COMMAND  PID    USER FD TYPE DEVICE SIZE/OFF NODE NAME
            //   node     1234   eve  20u IPv4 ...                 *:3000 (LISTEN)
            // We only care about the first column (command) and the NAME
            // column ("…:port (LISTEN)" or "…:port->…" — only LISTEN lines
            // reach us because we pass `-sTCP:LISTEN`).
            let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard fields.count >= 9 else { continue }
            if fields[0] == "COMMAND" { continue } // header
            let command = fields[0]
            let nameField = fields[8]
            guard let port = parseListenPort(from: nameField) else { continue }
            ports.insert(port)
            names.insert(command)
        }
        return Result(
            ports: Array(ports).sorted(),
            processNames: Array(names).sorted()
        )
    }

    /// Extract the port from an `lsof` NAME column entry. Handles
    /// `*:3000`, `127.0.0.1:8080`, `[::1]:3000`, and the rarer
    /// `127.0.0.1:54321->127.0.0.1:3000` form (we want the listener
    /// side, i.e. the part before `->`).
    static func parseListenPort(from nameField: String) -> Int? {
        let trimmed = nameField
            .replacingOccurrences(of: "(LISTEN)", with: "")
            .trimmingCharacters(in: .whitespaces)
        // Strip a peer address after `->` first so `lastIndex(of: ":")`
        // doesn't lock onto the remote port.
        let listenerSide: String
        if let arrowRange = trimmed.range(of: "->") {
            listenerSide = String(trimmed[..<arrowRange.lowerBound])
        } else {
            listenerSide = trimmed
        }
        guard let colonIndex = listenerSide.lastIndex(of: ":") else { return nil }
        let portSlice = listenerSide[listenerSide.index(after: colonIndex)...]
        let digits = portSlice.prefix { $0.isNumber }
        guard !digits.isEmpty, let port = Int(digits) else { return nil }
        return port
    }

    private static func inspect(
        pids: [pid_t],
        runner: ShellCommandRunner
    ) async -> Result {
        // -aPn  combine filters / numeric port / numeric host
        // -iTCP only TCP sockets
        // -sTCP:LISTEN only listening
        // -p <pid>,<pid>,...  scope to the process tree
        var arguments = ["-aPn", "-iTCP", "-sTCP:LISTEN", "-p", pids.map(String.init).joined(separator: ",")]
        do {
            let result = try await runner.run(
                executable: "/usr/sbin/lsof",
                arguments: arguments,
                timeout: 2
            )
            // lsof returns 1 when nothing matches the filter — that's fine.
            guard result.exitCode == 0 || result.exitCode == 1 else {
                return Result(ports: [], processNames: [])
            }
            return parse(result.stdout)
        } catch {
            // Fall back to the more common path when the system lsof moved.
            arguments = ["-aPn", "-iTCP", "-sTCP:LISTEN", "-p", pids.map(String.init).joined(separator: ",")]
            do {
                let result = try await runner.run(
                    executable: "/usr/bin/lsof",
                    arguments: arguments,
                    timeout: 2
                )
                guard result.exitCode == 0 || result.exitCode == 1 else {
                    return Result(ports: [], processNames: [])
                }
                return parse(result.stdout)
            } catch {
                return Result(ports: [], processNames: [])
            }
        }
    }
}
