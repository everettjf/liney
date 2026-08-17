//
//  LineyURLSchemeSupport.swift
//  Liney
//
//  Author: everettjf
//

import AppKit
import Foundation
import Security

protocol URLSchemeTokenStoring {
    func load() -> String?
    @discardableResult func save(_ token: String) -> Bool
    func delete()
}

struct URLSchemeTokenKeychainStore: URLSchemeTokenStoring {
    static let service = "com.liney.url-scheme"
    static let account = "command-token"

    func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func save(_ token: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
        let updateStatus = SecItemUpdate(
            identity as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        var item = identity
        item.merge([
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]) { _, newValue in newValue }
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum LineyURLScheme {
    static let scheme = "liney"
    static let tokenDefaultsKey = "com.everettjf.liney.urlScheme.token"
    static let enabledDefaultsKey = "com.everettjf.liney.urlScheme.enabled"
    static let skipConfirmationDefaultsKey = "com.everettjf.liney.urlScheme.skipConfirmation"

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

    /// When true, incoming URLs whose token already matches are executed
    /// without a confirmation dialog. Defaults to `false` so first-run
    /// behavior still prompts the user.
    static func skipConfirmation() -> Bool {
        UserDefaults.standard.bool(forKey: skipConfirmationDefaultsKey)
    }

    static func setSkipConfirmation(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: skipConfirmationDefaultsKey)
    }

    static func storedToken(
        tokenStore: any URLSchemeTokenStoring = URLSchemeTokenKeychainStore(),
        defaults: UserDefaults = .standard
    ) -> String? {
        if let value = normalizedToken(tokenStore.load()) {
            return value
        }

        // One-time migration from releases that kept this command-execution
        // credential in plaintext UserDefaults.
        guard let legacy = normalizedToken(defaults.string(forKey: tokenDefaultsKey)) else {
            return nil
        }
        guard tokenStore.save(legacy) else { return legacy }
        defaults.removeObject(forKey: tokenDefaultsKey)
        return legacy
    }

    @discardableResult
    static func setStoredToken(
        _ token: String?,
        tokenStore: any URLSchemeTokenStoring = URLSchemeTokenKeychainStore(),
        defaults: UserDefaults = .standard
    ) -> Bool {
        if let trimmed = normalizedToken(token) {
            guard tokenStore.save(trimmed) else { return false }
            defaults.removeObject(forKey: tokenDefaultsKey)
        } else {
            tokenStore.delete()
            defaults.removeObject(forKey: tokenDefaultsKey)
        }
        return true
    }

    static func generateToken() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    private static func normalizedToken(_ token: String?) -> String? {
        let value = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
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
