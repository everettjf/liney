//
//  WorkspaceStoreTests.swift
//  LineyTests
//
//  Author: everettjf
//

import XCTest
@testable import Liney

@MainActor
final class WorkspaceStoreTests: XCTestCase {
    func testOpenWorkspaceAsRepositoryAddsRepositoryWorkspaceWithoutChangingLocalWorkspace() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        try runProcess(
            executable: "/usr/bin/env",
            arguments: ["git", "init", "-b", "main"],
            currentDirectory: directoryURL.path
        )

        let store = WorkspaceStore(persistsWorkspaceState: false)
        let localWorkspace = WorkspaceModel(localDirectoryPath: directoryURL.path, name: "demo")
        store.workspaces = [localWorkspace]
        store.selectedWorkspaceID = localWorkspace.id

        try await store.openWorkspaceAsRepository(localWorkspace, persistAfterChange: false)

        XCTAssertEqual(store.workspaces.count, 2)
        XCTAssertEqual(store.workspaces.filter { !$0.supportsRepositoryFeatures }.count, 1)
        XCTAssertEqual(store.workspaces.filter(\.supportsRepositoryFeatures).count, 1)
        XCTAssertTrue(store.workspaces.contains(where: { $0.id == localWorkspace.id && !$0.supportsRepositoryFeatures }))
        XCTAssertEqual(
            store.workspaces.first(where: \.supportsRepositoryFeatures).map {
                URL(fileURLWithPath: $0.repositoryRoot).standardizedFileURL.path
            },
            directoryURL.standardizedFileURL.path
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
        let directoryURL = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private func runProcess(
        executable: String,
        arguments: [String],
        currentDirectory: String
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stdout = String(decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let stderr = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            XCTFail("Command failed: \(arguments.joined(separator: " "))\nstdout: \(stdout)\nstderr: \(stderr)")
            return
        }
    }
}
