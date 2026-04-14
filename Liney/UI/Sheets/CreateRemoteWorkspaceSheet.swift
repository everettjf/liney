//
//  CreateRemoteWorkspaceSheet.swift
//  Liney
//
//  Author: everettjf
//

import SwiftUI

struct CreateRemoteWorkspaceSheet: View {
    let onCreate: (SSHSessionConfiguration, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var localization = LocalizationManager.shared

    @State private var sshEntries: [SSHConfigEntry] = []
    @State private var selectedEntryIndex: Int?
    @State private var host = ""
    @State private var user = ""
    @State private var port = "22"
    @State private var identityFile = ""
    @State private var remotePath = ""
    @State private var workspaceName = ""
    @State private var connectionStatus: SSHConnectionStatus?
    @State private var isTesting = false
    @State private var showDirectoryBrowser = false

    private func localized(_ key: String) -> String {
        LocalizationManager.shared.string(key)
    }

    private var canCreate: Bool {
        !host.isEmpty && !workspaceName.isEmpty
    }

    private var currentConfiguration: SSHSessionConfiguration {
        SSHSessionConfiguration(
            host: host,
            user: user.isEmpty ? nil : user,
            port: Int(port) ?? 22,
            identityFilePath: identityFile.isEmpty ? nil : identityFile,
            remoteWorkingDirectory: remotePath.isEmpty ? nil : remotePath
        )
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

    private func testConnection() {
        isTesting = true
        connectionStatus = nil
        let entry = currentEntry
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
            Text(localized("sheet.remote.title"))
                .font(.system(size: 18, weight: .semibold))

            Text(localized("sheet.remote.description"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            // SSH Config picker
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

            // Connection fields
            GroupBox(localized("sheet.remote.connection")) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField(localized("sheet.ssh.host"), text: $host)
                    TextField(localized("sheet.ssh.user"), text: $user)
                    TextField(localized("sheet.ssh.port"), text: $port)
                    TextField(localized("sheet.ssh.identityFile"), text: $identityFile)
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

            // Workspace name
            GroupBox(localized("sheet.remote.name")) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField(localized("sheet.remote.namePlaceholder"), text: $workspaceName)
                }
                .textFieldStyle(.roundedBorder)
                .padding(.top, 8)
            }

            // Buttons
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Label(localized("common.cancel"), systemImage: "xmark")
                }
                Button {
                    onCreate(currentConfiguration, workspaceName)
                    dismiss()
                } label: {
                    Label(localized("sheet.remote.create"), systemImage: "plus")
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
        .sheet(isPresented: $showDirectoryBrowser) {
            RemoteDirectoryBrowser(sshConfig: currentConfiguration) { selectedPath in
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
}
