//
//  RemoteDirectoryBrowser.swift
//  Liney
//
//  Author: everettjf
//

import SwiftUI

// MARK: - DirectoryRowView

/// Extracted into its own View to support recursive DisclosureGroup rendering.
private struct DirectoryRowView: View {
    @ObservedObject var node: DirectoryNode
    @Binding var selectedPath: String?
    let expandAction: (DirectoryNode) async -> Void

    private var isSelected: Bool {
        selectedPath == node.path
    }

    var body: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { node.isExpanded },
            set: { newValue in
                if newValue {
                    Task { await expandAction(node) }
                } else {
                    node.isExpanded = false
                }
            }
        )) {
            if node.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.leading, 8)
            } else if let error = node.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            } else {
                ForEach(node.children) { child in
                    DirectoryRowView(
                        node: child,
                        selectedPath: $selectedPath,
                        expandAction: expandAction
                    )
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: 13))
                Text(node.name)
                    .lineLimit(1)
                    .font(.system(size: 13))
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isSelected ? Color(nsColor: LineyTheme.sidebarSelectionFill) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(isSelected ? Color(nsColor: LineyTheme.sidebarSelectionStroke) : Color.clear, lineWidth: 1)
            )
            .onTapGesture {
                selectedPath = node.path
            }
        }
    }
}

// MARK: - RemoteDirectoryBrowser

struct RemoteDirectoryBrowser: View {
    let sshConfig: SSHSessionConfiguration
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var localization = LocalizationManager.shared
    @StateObject private var viewModel: RemoteDirectoryBrowserViewModel

    init(sshConfig: SSHSessionConfiguration, onSelect: @escaping (String) -> Void) {
        self.sshConfig = sshConfig
        self.onSelect = onSelect
        _viewModel = StateObject(wrappedValue: RemoteDirectoryBrowserViewModel(sshConfig: sshConfig))
    }

    private func localized(_ key: String) -> String {
        localization.string(key)
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            pathBar
            Divider()
            contentArea
            Divider()
            bottomBar
        }
        .frame(width: 480, height: 420)
        .task {
            await viewModel.connect()
        }
        .onDisappear {
            Task { await viewModel.disconnect() }
        }
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localized("remote.browser.title"))
                .font(.system(size: 16, weight: .semibold))
            Text(sshConfig.destination)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(LineyTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Path Bar

    private var pathBar: some View {
        HStack(spacing: 8) {
            Text(localized("remote.browser.path"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("", text: $viewModel.currentPath)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .onSubmit {
                    Task {
                        await viewModel.navigateTo(path: viewModel.currentPath)
                    }
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        switch viewModel.connectionState {
        case .idle, .connecting:
            Spacer()
            ProgressView(localized("remote.browser.connecting"))
            Spacer()

        case .connected:
            if viewModel.rootNodes.isEmpty {
                Spacer()
                ContentUnavailableView(
                    localized("remote.browser.empty"),
                    systemImage: "folder"
                )
                Spacer()
            } else {
                List {
                    ForEach(viewModel.rootNodes) { node in
                        DirectoryRowView(
                            node: node,
                            selectedPath: $viewModel.selectedPath,
                            expandAction: { n in
                                await viewModel.expandNode(n)
                            }
                        )
                    }
                }
                .listStyle(.sidebar)
            }

        case .passwordRequired:
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "key.slash")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text(localized("remote.browser.passwordRequired"))
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                SecureField(localized("remote.browser.password"), text: $viewModel.password)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                    .onSubmit {
                        Task { await viewModel.connectWithPassword() }
                    }
                Button(localized("remote.browser.connect")) {
                    Task { await viewModel.connectWithPassword() }
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
            .padding(.horizontal, 16)

        case .error(let message):
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32))
                    .foregroundStyle(.red)
                Text(message)
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            if let selected = viewModel.selectedPath {
                Text(selected)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(LineyTheme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text(localized("remote.browser.noSelection"))
                    .font(.system(size: 11))
                    .foregroundStyle(LineyTheme.mutedText)
            }

            Spacer()

            Button(localized("common.cancel")) {
                Task { await viewModel.disconnect() }
                dismiss()
            }

            Button(localized("remote.browser.open")) {
                if let path = viewModel.selectedPath {
                    Task { await viewModel.disconnect() }
                    onSelect(path)
                    dismiss()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.selectedPath == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
