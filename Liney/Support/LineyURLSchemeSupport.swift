//
//  LineyURLSchemeSupport.swift
//  Liney
//
//  Author: everettjf
//

import AppKit
import Foundation

enum LineyURLScheme {
    static let scheme = "liney"
    static let tokenDefaultsKey = "com.everettjf.liney.urlScheme.token"
    static let enabledDefaultsKey = "com.everettjf.liney.urlScheme.enabled"
    static let confirmEachRequestDefaultsKey = "com.everettjf.liney.urlScheme.confirmEachRequest"

    struct RunRequest {
        let cmd: String
        let cwd: String
        let token: String?
    }

    static func isEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: enabledDefaultsKey)
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledDefaultsKey)
    }

    /// Whether a confirmation dialog is shown for every incoming URL.
    /// Defaults to `true` when no preference has been written yet, so
    /// first-run behavior stays safe.
    static func confirmEachRequest() -> Bool {
        if UserDefaults.standard.object(forKey: confirmEachRequestDefaultsKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: confirmEachRequestDefaultsKey)
    }

    static func setConfirmEachRequest(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: confirmEachRequestDefaultsKey)
    }

    static func storedToken() -> String? {
        let value = UserDefaults.standard.string(forKey: tokenDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    static func setStoredToken(_ token: String?) {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            UserDefaults.standard.set(trimmed, forKey: tokenDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: tokenDefaultsKey)
        }
    }

    static func generateToken() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    /// Parses `liney://run?cmd=...&cwd=...&token=...`.
    /// Returns nil if the URL is not a well-formed run request.
    static func parseRunURL(_ url: URL) -> RunRequest? {
        guard url.scheme == scheme, url.host == "run" else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return nil }

        var cmd = ""
        var cwd = ""
        var token: String? = nil
        for item in items {
            switch item.name {
            case "cmd": cmd = item.value ?? ""
            case "cwd": cwd = item.value ?? ""
            case "token": token = item.value
            default: break
            }
        }

        let trimmedCmd = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCwd = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCmd.isEmpty, !trimmedCwd.isEmpty else { return nil }
        return RunRequest(cmd: trimmedCmd, cwd: trimmedCwd, token: token)
    }
}
