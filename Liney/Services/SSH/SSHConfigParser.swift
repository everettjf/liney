//
//  SSHConfigParser.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

/// A parsed entry from an SSH config file.
struct SSHConfigEntry: Hashable, Sendable {
    let displayName: String   // Host alias
    let host: String          // HostName (or Host if HostName missing)
    let port: Int             // default 22
    let user: String?
    let identityFile: String?
}

/// Parses OpenSSH config files into SSHConfigEntry models.
enum SSHConfigParser {

    /// Parse an SSH config file at the given path.
    static func parse(configPath: String = "~/.ssh/config") -> [SSHConfigEntry] {
        let expandedPath = (configPath as NSString).expandingTildeInPath
        guard let contents = try? String(contentsOfFile: expandedPath, encoding: .utf8) else {
            return []
        }
        return parse(from: contents)
    }

    /// Parse SSH config text content into SSHConfigEntry list.
    static func parse(from contents: String) -> [SSHConfigEntry] {
        var entries: [SSHConfigEntry] = []
        var currentHosts: [String] = []
        var hostName: String?
        var port: Int = 22
        var user: String?
        var identityFile: String?

        func flushCurrent() {
            for host in currentHosts {
                // Skip wildcard and pattern hosts
                guard !host.contains("*") && !host.contains("?") else {
                    continue
                }
                let resolvedHostName = hostName ?? host
                entries.append(SSHConfigEntry(
                    displayName: host,
                    host: resolvedHostName,
                    port: port,
                    user: user,
                    identityFile: identityFile
                ))
            }
            resetFields()
        }

        func resetFields() {
            currentHosts = []
            hostName = nil
            port = 22
            user = nil
            identityFile = nil
        }

        let lines = contents.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            // Normalize `=` separator to space so "HostName=foo" and "Host = bar" are handled
            let normalized = trimmed.replacingOccurrences(of: "=", with: " ")

            // Split into keyword and value (handles both spaces and tabs)
            let parts = normalized.split(maxSplits: 1, whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count == 2 else { continue }

            let keyword = parts[0].lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            switch keyword {
            case "host":
                flushCurrent()
                // Support multi-pattern Host lines: "Host server1 server2"
                currentHosts = value.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            case "hostname":
                hostName = value
            case "port":
                port = Int(value) ?? 22
            case "user":
                user = value
            case "identityfile":
                identityFile = value
            default:
                break
            }
        }

        // Flush last entry
        flushCurrent()

        return entries
    }
}
