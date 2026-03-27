//
//  HAPIIntegrationSupport.swift
//  Liney
//
//  Author: Codex
//

import Foundation

private func lineyLocalizedHAPIString(_ key: String) -> String {
    LocalizationManager.shared.string(key)
}

struct HAPIInstallationStatus: Hashable {
    var executablePath: String
    var cloudflaredExecutablePath: String? = nil

    var primaryActionTitle: String {
        lineyLocalizedHAPIString("main.hapi.claudeCode")
    }

    var primaryActionHelpText: String {
        lineyLocalizedHAPIString("main.hapi.help.launch")
    }
}

enum HAPIIntegrationState: Hashable {
    case unavailable
    case available(HAPIInstallationStatus)
}

enum HAPIIntegrationCatalog {
    static func detect(using runner: ShellCommandRunner = ShellCommandRunner()) async -> HAPIIntegrationState {
        guard let executablePath = await resolveExecutablePath(named: "hapi", using: runner) else {
            return .unavailable
        }

        let cloudflaredExecutablePath = await resolveExecutablePath(named: "cloudflared", using: runner)
        return .available(
            HAPIInstallationStatus(
                executablePath: executablePath,
                cloudflaredExecutablePath: cloudflaredExecutablePath
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

    private static func resolveExecutablePath(
        named executableName: String,
        using runner: ShellCommandRunner
    ) async -> String? {
        do {
            let result = try await runner.run(
                executable: "/bin/zsh",
                arguments: ["-lic", "whence -p \(executableName.shellQuoted)"]
            )
            return parseExecutablePath(result.stdout)
        } catch {
            return nil
        }
    }
}
