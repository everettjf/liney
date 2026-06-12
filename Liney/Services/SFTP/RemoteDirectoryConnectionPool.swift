//
//  RemoteDirectoryConnectionPool.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

/// Reuses one connected `SFTPService` per SSH target so the file tree can list
/// remote directories repeatedly (root, expanded rows, refresh) without paying
/// the connect cost on every read.
///
/// Connections are cached by `SSHSessionConfiguration`. A failed listing drops
/// the cached service so the next attempt reconnects from scratch.
actor RemoteDirectoryConnectionPool {

    static let shared = RemoteDirectoryConnectionPool()

    private var services: [SSHSessionConfiguration: SFTPService] = [:]

    /// List files and directories at `path` on the given remote host.
    func listEntries(
        config: SSHSessionConfiguration,
        path: String,
        includesHidden: Bool
    ) async throws -> SFTPDirectoryListing {
        do {
            let service = try await service(for: config)
            return try await service.listEntries(at: path, includesHidden: includesHidden)
        } catch {
            services[config] = nil
            throw error
        }
    }

    private func service(for config: SSHSessionConfiguration) async throws -> SFTPService {
        if let existing = services[config] {
            return existing
        }
        let service = SFTPService()
        try await service.connect(target: config)
        services[config] = service
        return service
    }
}
