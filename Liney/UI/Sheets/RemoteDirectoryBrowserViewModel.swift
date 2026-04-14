//
//  RemoteDirectoryBrowserViewModel.swift
//  Liney
//
//  Author: everettjf
//

import Combine
import SwiftUI

// MARK: - DirectoryNode

@MainActor
final class DirectoryNode: ObservableObject, Identifiable {
    let id = UUID()
    let name: String
    let path: String
    @Published var children: [DirectoryNode] = []
    @Published var isExpanded = false
    @Published var isLoading = false
    @Published var error: String?

    init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

// MARK: - RemoteDirectoryBrowserViewModel

@MainActor
final class RemoteDirectoryBrowserViewModel: ObservableObject {

    enum ConnectionState: Equatable {
        case idle
        case connecting
        case connected
        case passwordRequired
        case error(String)
    }

    let sshConfig: SSHSessionConfiguration

    @Published var connectionState: ConnectionState = .idle
    @Published var rootNodes: [DirectoryNode] = []
    @Published var currentPath: String = ""
    @Published var selectedPath: String? = nil
    @Published var password: String = ""

    private let sftpService = SFTPService()

    init(sshConfig: SSHSessionConfiguration) {
        self.sshConfig = sshConfig
    }

    // MARK: - Public API

    func connect() async {
        connectionState = .connecting
        do {
            try await sftpService.connect(target: sshConfig)
            connectionState = .connected

            let home = try await sftpService.homeDirectory()
            currentPath = home
            selectedPath = home
            await loadDirectory(at: home)
        } catch let error as SFTPServiceError where error == .authenticationFailed {
            connectionState = .passwordRequired
        } catch {
            connectionState = .error(error.localizedDescription)
        }
    }

    func connectWithPassword() async {
        // TODO: Citadel integration for password-based authentication
        connectionState = .error("Password authentication not yet supported. Please configure SSH key auth.")
    }

    func loadDirectory(at path: String) async {
        do {
            let entries = try await sftpService.listDirectories(at: path)
            rootNodes = entries.map { DirectoryNode(name: $0.name, path: $0.path) }
        } catch {
            connectionState = .error(error.localizedDescription)
        }
    }

    func expandNode(_ node: DirectoryNode) async {
        guard !node.isLoading else { return }

        if node.isExpanded {
            node.isExpanded = false
            return
        }

        node.isLoading = true
        node.error = nil

        do {
            let entries = try await sftpService.listDirectories(at: node.path)
            node.children = entries.map { DirectoryNode(name: $0.name, path: $0.path) }
            node.isExpanded = true
        } catch {
            node.error = error.localizedDescription
        }

        node.isLoading = false
    }

    func navigateTo(path: String) async {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        currentPath = trimmed
        selectedPath = trimmed
        await loadDirectory(at: trimmed)
    }

    func disconnect() async {
        await sftpService.disconnect()
        connectionState = .idle
        rootNodes = []
        selectedPath = nil
    }
}
