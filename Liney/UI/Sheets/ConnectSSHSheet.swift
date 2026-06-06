//
//  ConnectSSHSheet.swift
//  Liney
//
//  Author: everettjf
//

import SwiftUI

struct ConnectSSHSheet: View {
    let request: ConnectSSHRequest
    let onCreate: (SSHSessionConfiguration, String, ConnectSSHMode, UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var localization = LocalizationManager.shared

    @State private var mode: ConnectSSHMode
    @State private var sshEntries: [SSHConfigEntry] = []
    @State private var selectedEntryIndex: Int?
    @State private var selectedPresetID: UUID?
    @State private var presetCommand = ""
    @State private var host = ""
    @State private var user = ""
    @State private var port = "22"
    @State private var identityFile = ""
    @State private var password = ""
    @State private var remotePath = ""
    @State private var workspaceName = ""
    @State private var connectionStatus: SSHConnectionStatus?
    @State private var isTesting = false
    @State private var showDirectoryBrowser = false
    /// Account most recently saved to the Keychain during this sheet session, so
    /// editing host/user/port and re-saving can clean up the now-orphaned entry.
    @State private var lastPersistedAccount: String?
    /// Bumped after a Keychain mutation to force the password field's placeholder
    /// and the clear button to re-evaluate `SSHPasswordStore.hasPassword`.
    @State private var keychainRefreshToken = 0

    init(
        request: ConnectSSHRequest,
        onCreate: @escaping (SSHSessionConfiguration, String, ConnectSSHMode, UUID?) -> Void
    ) {
        self.request = request
        self.onCreate = onCreate
        _mode = State(initialValue: request.preferredMode)
        _selectedPresetID = State(initialValue: request.preferredPresetID)
    }

    private func localized(_ key: String) -> String {
        LocalizationManager.shared.string(key)
    }

    private var canCreate: Bool {
        guard !host.isEmpty else { return false }
        switch mode {
        case .remoteWorkspace:
            return !workspaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .terminalOnly:
            return true
        }
    }

    private var currentConfiguration: SSHSessionConfiguration {
        let trimmedCommand = presetCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        return SSHSessionConfiguration(
            host: host,
            user: user.isEmpty ? nil : user,
            port: Int(port) ?? 22,
            identityFilePath: identityFile.isEmpty ? nil : identityFile,
            remoteWorkingDirectory: remotePath.isEmpty ? nil : remotePath,
            remoteCommand: trimmedCommand.isEmpty ? nil : trimmedCommand
        )
    }

    /// Stable Keychain account for the host/user/port currently in the form.
    private var keychainAccount: String {
        SSHPasswordStore.account(
            host: host,
            user: user.isEmpty ? nil : user,
            port: Int(port)
        )
    }

    /// Whether a password is already stored for the host/user/port in the form.
    /// Reads `keychainRefreshToken` so the view re-evaluates after a mutation.
    private var hasStoredPassword: Bool {
        _ = keychainRefreshToken
        return !host.isEmpty && SSHPasswordStore.hasPassword(account: keychainAccount)
    }

    /// Placeholder hints whether a password is already stored for this host so
    /// the user knows an empty field will reuse it rather than clear it.
    private var passwordPlaceholder: String {
        hasStoredPassword ? localized("sheet.ssh.password.stored") : localized("sheet.ssh.password")
    }

    /// Persists a freshly typed password to the Keychain and returns the account
    /// to attach to a connection, or `nil` when there is no password to use.
    /// Side-effecting, so call only from user-initiated actions.
    private func persistedPasswordAccount() -> String? {
        let account = keychainAccount
        guard !password.isEmpty else {
            return SSHPasswordStore.hasPassword(account: account) ? account : nil
        }
        // The form may have changed host/user/port since the last save, which
        // would strand the secret under the old account name. Drop that orphan
        // before writing the new one. Keychain writes run synchronously so the
        // secret is ready for the caller; only the @State update is deferred to
        // avoid mutating state mid view-update (this runs from the sheet body).
        if let previous = lastPersistedAccount, previous != account {
            SSHPasswordStore.delete(account: previous)
        }
        SSHPasswordStore.save(account: account, password: password)
        DispatchQueue.main.async {
            lastPersistedAccount = account
            keychainRefreshToken += 1
        }
        return account
    }

    /// Removes the stored password for the current host/user/port and clears the
    /// field. Invoked from the clear button, so mutating state directly is safe.
    private func clearStoredPassword() {
        let account = keychainAccount
        SSHPasswordStore.delete(account: account)
        if lastPersistedAccount == account {
            lastPersistedAccount = nil
        }
        password = ""
        keychainRefreshToken += 1
    }

    /// Builds the configuration to launch/browse, tagging it so ssh fetches the
    /// stored password via SSH_ASKPASS.
    private func preparedConfiguration() -> SSHSessionConfiguration {
        var configuration = currentConfiguration
        configuration.passwordKeychainAccount = persistedPasswordAccount()
        return configuration
    }

    private var currentEntry: SSHConfigEntry {
        SSHConfigEntry(
            displayName: host,
            host: host,
            port: Int(port) ?? 22,
            user: user.isEmpty ? nil : user,
            identityFile: identityFile.isEmpty ? nil : identityFile
        )
    }

    private func applyEntry(_ index: Int?) {
        guard let index, index < sshEntries.count else { return }
        let entry = sshEntries[index]
        host = entry.host
        user = entry.user ?? ""
        port = String(entry.port)
        identityFile = entry.identityFile ?? ""
        connectionStatus = nil
    }

    private func applyPreset(_ presetID: UUID?) {
        guard let presetID,
              let preset = request.presets.first(where: { $0.id == presetID }) else {
            presetCommand = ""
            return
        }
        if let presetHost = preset.host, !presetHost.isEmpty {
            host = presetHost
        }
        if let presetUser = preset.user, !presetUser.isEmpty {
            user = presetUser
        }
        if let presetPort = preset.port {
            port = String(presetPort)
        }
        if let presetIdentity = preset.identityFilePath, !presetIdentity.isEmpty {
            identityFile = presetIdentity
        }
        if let presetWorkingDir = preset.remoteWorkingDirectory, !presetWorkingDir.isEmpty {
            remotePath = presetWorkingDir
        }
        presetCommand = preset.remoteCommand
        connectionStatus = nil
    }

    private func testConnection() {
        isTesting = true
        connectionStatus = nil
        var entry = currentEntry
        entry.passwordKeychainAccount = persistedPasswordAccount()
        Task {
            let service = SSHConfigService()
            let status = await service.testConnection(entry)
            await MainActor.run {
                connectionStatus = status
                isTesting = false
            }
        }
    }

    @ViewBuilder
    private var connectionStatusIcon: some View {
        if isTesting {
            ProgressView()
                .controlSize(.small)
        } else if let status = connectionStatus {
            switch status {
            case .connected:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .authRequired:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
            case .unreachable(let error):
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .help(error.localizedDescription)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localized("sheet.connectSSH.title"))
                .font(.system(size: 18, weight: .semibold))

            Text(localized("sheet.connectSSH.description"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Picker("", selection: $mode) {
                Text(localized("sheet.connectSSH.mode.remoteWorkspace"))
                    .tag(ConnectSSHMode.remoteWorkspace)
                Text(localized("sheet.connectSSH.mode.terminalOnly"))
                    .tag(ConnectSSHMode.terminalOnly)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(modeHint)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if !request.presets.isEmpty {
                GroupBox(localized("sheet.ssh.preset")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker(localized("sheet.ssh.preset"), selection: $selectedPresetID) {
                            Text(localized("sheet.ssh.noPreset"))
                                .tag(Optional<UUID>.none)
                            ForEach(request.presets) { preset in
                                Text(preset.name).tag(Optional(preset.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.top, 8)
                }
                .onChange(of: selectedPresetID) { _, newValue in
                    applyPreset(newValue)
                }
            }

            if !sshEntries.isEmpty {
                GroupBox(localized("sheet.remote.sshConfig")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker(localized("sheet.remote.sshConfig"), selection: $selectedEntryIndex) {
                            Text(localized("sheet.remote.manual"))
                                .tag(Optional<Int>.none)
                            ForEach(Array(sshEntries.enumerated()), id: \.offset) { index, entry in
                                Text(entry.displayName).tag(Optional(index))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.top, 8)
                }
                .onChange(of: selectedEntryIndex) { _, newValue in
                    applyEntry(newValue)
                }
            }

            GroupBox(localized("sheet.remote.connection")) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField(localized("sheet.ssh.host"), text: $host)
                    TextField(localized("sheet.ssh.user"), text: $user)
                    TextField(localized("sheet.ssh.port"), text: $port)
                    TextField(localized("sheet.ssh.identityFile"), text: $identityFile)
                    HStack {
                        SecureField(passwordPlaceholder, text: $password)
                        if hasStoredPassword {
                            Button {
                                clearStoredPassword()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help(localized("sheet.ssh.password.clear"))
                        }
                    }
                    Text(localized("sheet.ssh.password.hint"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField(localized("sheet.ssh.remoteWorkingDirectory"), text: $remotePath)
                        Button(localized("sheet.remote.browse")) {
                            showDirectoryBrowser = true
                        }
                        .disabled(host.isEmpty)
                    }

                    HStack {
                        Button {
                            testConnection()
                        } label: {
                            Label(localized("sheet.remote.testConnection"), systemImage: "bolt.horizontal")
                        }
                        .disabled(host.isEmpty || isTesting)

                        connectionStatusIcon
                    }
                }
                .textFieldStyle(.roundedBorder)
                .padding(.top, 8)
            }

            if mode == .remoteWorkspace {
                GroupBox(localized("sheet.remote.name")) {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField(localized("sheet.remote.namePlaceholder"), text: $workspaceName)
                    }
                    .textFieldStyle(.roundedBorder)
                    .padding(.top, 8)
                }
            }

            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Label(localized("common.cancel"), systemImage: "xmark")
                }
                Button {
                    onCreate(preparedConfiguration(), workspaceName, mode, selectedPresetID)
                    dismiss()
                } label: {
                    Label(createButtonLabel, systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canCreate)
                .keyboardShortcut(.defaultAction)
            }
        }
        .task {
            let service = SSHConfigService()
            sshEntries = await service.loadSSHConfig()
        }
        .onAppear {
            if let presetID = selectedPresetID {
                applyPreset(presetID)
            }
        }
        .sheet(isPresented: $showDirectoryBrowser) {
            RemoteDirectoryBrowser(sshConfig: preparedConfiguration()) { selectedPath in
                remotePath = selectedPath
                if workspaceName.isEmpty {
                    let lastComponent = (selectedPath as NSString).lastPathComponent
                    if !lastComponent.isEmpty && lastComponent != "/" {
                        workspaceName = lastComponent
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private var modeHint: String {
        switch mode {
        case .remoteWorkspace:
            return localized("sheet.connectSSH.mode.remoteWorkspace.hint")
        case .terminalOnly:
            return localized("sheet.connectSSH.mode.terminalOnly.hint")
        }
    }

    private var createButtonLabel: String {
        switch mode {
        case .remoteWorkspace:
            return localized("sheet.remote.create")
        case .terminalOnly:
            return localized("sheet.ssh.create")
        }
    }
}
