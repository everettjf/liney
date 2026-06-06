//
//  SSHPasswordStore.swift
//  Liney
//
//  Author: everettjf
//

import Foundation
import Security

/// Stores SSH passwords in the macOS login Keychain and provides the
/// `SSH_ASKPASS` helper that lets `/usr/bin/ssh` fetch them non-interactively.
///
/// Why this shape:
/// - OpenSSH never reads the password from argv/stdin (only from the controlling
///   tty), so the only safe way to automate it is the `SSH_ASKPASS` hook.
/// - We never persist the plaintext password in the workspace state JSON. The
///   `SSHSessionConfiguration` only carries a non-secret keychain *account*
///   string; the secret itself lives in the Keychain.
/// - The helper is a tiny shell script that shells out to `/usr/bin/security`
///   to read the secret lazily *at the moment ssh asks*. We never put the
///   password into ssh's argv or environment, both of which a same-user process
///   can read via `KERN_PROCARGS2`.
enum SSHPasswordStore {
    /// Keychain generic-password service shared by every Liney SSH secret.
    static let keychainService = "com.liney.ssh"

    /// Derives a stable, non-secret keychain account from a connection so the
    /// same host+user+port reuses one stored password across reconnects.
    nonisolated static func account(host: String, user: String?, port: Int?) -> String {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = (user ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(trimmedUser)@\(trimmedHost):\(port ?? 22)"
    }

    // MARK: - Keychain CRUD

    /// Saves (or replaces) the password for `account`. An empty password deletes
    /// the entry instead so toggling the field off clears the stored secret.
    @discardableResult
    nonisolated static func save(account: String, password: String) -> Bool {
        guard !password.isEmpty else {
            delete(account: account)
            return true
        }
        guard let passwordData = password.data(using: .utf8) else { return false }

        // Remove any existing entry first so we can attach a fresh access ACL
        // that trusts `/usr/bin/security` (used by the askpass helper).
        delete(account: account)

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: passwordData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        if let access = makeHelperAccess() {
            query[kSecAttrAccess as String] = access
        }

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    nonisolated static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }
        return password
    }

    nonisolated static func hasPassword(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    nonisolated static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Builds an access object that trusts this app plus `/usr/bin/security`,
    /// so the askpass helper can read the secret without a Keychain prompt.
    /// Returns `nil` on failure; the caller then falls back to the default ACL
    /// (the helper's first read will surface a one-time "Always Allow" prompt).
    nonisolated private static func makeHelperAccess() -> SecAccess? {
        var selfApp: SecTrustedApplication?
        var securityApp: SecTrustedApplication?
        SecTrustedApplicationCreateFromPath(nil, &selfApp)
        SecTrustedApplicationCreateFromPath("/usr/bin/security", &securityApp)

        let trusted = [selfApp, securityApp].compactMap { $0 }
        guard !trusted.isEmpty else { return nil }

        var access: SecAccess?
        let status = SecAccessCreate("Liney SSH password" as CFString, trusted as CFArray, &access)
        guard status == errSecSuccess else { return nil }
        return access
    }
}

// MARK: - Askpass helper

extension SSHPasswordStore {
    /// Environment variable the helper reads to learn which keychain account to
    /// fetch. Set on the ssh process by the launch path.
    static let askpassAccountEnvKey = "LINEY_SSH_ASKPASS_ACCOUNT"

    /// Environment that makes `/usr/bin/ssh` (or `sftp`) fetch the stored
    /// password through the askpass helper instead of prompting on a tty.
    /// Returns `nil` when no account is set or the helper can't be written, so
    /// callers fall back to their default (key-only / BatchMode) behaviour.
    ///
    /// Batch callers (no controlling terminal) must also drop `BatchMode=yes`
    /// and should add `-o NumberOfPasswordPrompts=1`, otherwise ssh still
    /// refuses the askpass path or retries indefinitely.
    nonisolated static func askpassEnvironment(account: String?) -> [String: String]? {
        guard let account, !account.isEmpty, let helperPath = ensureAskpassHelper() else {
            return nil
        }
        return [
            "SSH_ASKPASS": helperPath,
            "SSH_ASKPASS_REQUIRE": "force",
            askpassAccountEnvKey: account,
        ]
    }

    /// Ensures the askpass helper script exists on disk and returns its path,
    /// or `nil` if it could not be written. The script is regenerated whenever
    /// its contents differ, so updates ship automatically.
    nonisolated static func ensureAskpassHelper() -> String? {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = appSupport.appendingPathComponent("Liney", isDirectory: true)
        let helperURL = directory.appendingPathComponent("liney-ssh-askpass.sh")

        let script = """
        #!/bin/sh
        # Generated by Liney. Reads the SSH password from the macOS Keychain so
        # /usr/bin/ssh can authenticate non-interactively via SSH_ASKPASS.
        exec /usr/bin/security find-generic-password -s "\(keychainService)" -a "$\(askpassAccountEnvKey)" -w
        """

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let existing = try? String(contentsOf: helperURL, encoding: .utf8)
            if existing != script {
                try script.write(to: helperURL, atomically: true, encoding: .utf8)
            }
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helperURL.path)
        } catch {
            return nil
        }
        return helperURL.path
    }
}
