//
//  HAPIIntegrationSupport.swift
//  Liney
//
//  Author: Codex
//

import Foundation

enum HAPIPrimaryAction: Hashable {
    case launchSession
    case startHub
}

struct HAPIAuthStatus: Hashable {
    var apiURL: String?
    var hasToken: Bool
    var tokenSource: String?

    static func parse(_ output: String) -> HAPIAuthStatus {
        var apiURL: String?
        var hasToken = false
        var tokenSource: String?

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if let value = value(in: line, for: "HAPI_API_URL") {
                apiURL = value
                continue
            }

            if let value = value(in: line, for: "CLI_API_TOKEN") {
                hasToken = value.caseInsensitiveCompare("set") == .orderedSame
                continue
            }

            if let value = value(in: line, for: "Token Source") {
                tokenSource = value
            }
        }

        return HAPIAuthStatus(apiURL: apiURL, hasToken: hasToken, tokenSource: tokenSource)
    }

    private static func value(in line: String, for key: String) -> String? {
        guard line.hasPrefix("\(key):") else { return nil }
        return line
            .dropFirst(key.count + 1)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
}

struct HAPIInstallationStatus: Hashable {
    var executablePath: String
    var authStatus: HAPIAuthStatus

    var primaryAction: HAPIPrimaryAction {
        authStatus.hasToken ? .launchSession : .startHub
    }

    var primaryActionTitle: String {
        switch primaryAction {
        case .launchSession:
            return "Launch HAPI in Current Project"
        case .startHub:
            return "Start HAPI Hub"
        }
    }

    var primaryActionHelpText: String {
        switch primaryAction {
        case .launchSession:
            return "Launch HAPI in the current worktree"
        case .startHub:
            return "Quick Start step 1: start `hapi hub --relay`"
        }
    }

    var menuStatusText: String {
        if authStatus.hasToken {
            if let apiURL = authStatus.apiURL {
                return "Configured for \(apiURL)"
            }
            return "HAPI is configured"
        }
        return "Quick Start: start the hub first"
    }
}

enum HAPIIntegrationState: Hashable {
    case unavailable
    case available(HAPIInstallationStatus)
}

enum HAPIIntegrationCatalog {
    static func detect(using runner: ShellCommandRunner = ShellCommandRunner()) async -> HAPIIntegrationState {
        guard let executablePath = await resolveExecutablePath(using: runner) else {
            return .unavailable
        }

        let authStatus = await resolveAuthStatus(executablePath: executablePath, using: runner)
        return .available(
            HAPIInstallationStatus(
                executablePath: executablePath,
                authStatus: authStatus
            )
        )
    }

    static func parseExecutablePath(_ output: String) -> String? {
        let path = output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { $0.hasPrefix("/") })
        return path?.nilIfEmpty
    }

    private static func resolveExecutablePath(using runner: ShellCommandRunner) async -> String? {
        do {
            let result = try await runner.run(
                executable: "/bin/zsh",
                arguments: ["-lic", "whence -p hapi"]
            )
            return parseExecutablePath(result.stdout)
        } catch {
            return nil
        }
    }

    private static func resolveAuthStatus(
        executablePath: String,
        using runner: ShellCommandRunner
    ) async -> HAPIAuthStatus {
        do {
            let result = try await runner.run(
                executable: executablePath,
                arguments: ["auth", "status"]
            )
            return HAPIAuthStatus.parse(result.stdout + "\n" + result.stderr)
        } catch {
            return HAPIAuthStatus(apiURL: nil, hasToken: false, tokenSource: nil)
        }
    }
}
