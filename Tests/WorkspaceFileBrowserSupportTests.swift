import XCTest
@testable import Liney

final class WorkspaceFileBrowserSupportTests: XCTestCase {
    func testEnumerateFilesSkipsGitDirectory() throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        try FileManager.default.createDirectory(at: directoryURL.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try "hello".write(to: directoryURL.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "secret".write(to: directoryURL.appendingPathComponent(".git/config"), atomically: true, encoding: .utf8)

        let files = try WorkspaceFileBrowserSupport.enumerateFiles(in: directoryURL.path)

        XCTAssertEqual(files.map(\.relativePath), ["README.md"])
    }

    func testLoadPreviewRejectsLargeFiles() throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let fileURL = directoryURL.appendingPathComponent("large.txt")
        try String(repeating: "a", count: 64).write(to: fileURL, atomically: true, encoding: .utf8)

        let preview = try WorkspaceFileBrowserSupport.loadPreview(at: fileURL.path, maxBytes: 32)

        XCTAssertEqual(preview, .unsupported(reason: "large"))
    }

    func testSaveTextFileRoundTripsUTF8Contents() throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let fileURL = directoryURL.appendingPathComponent("notes.txt")
        try WorkspaceFileBrowserSupport.saveTextFile(contents: "hello\nworld\n", to: fileURL.path)

        let preview = try WorkspaceFileBrowserSupport.loadPreview(at: fileURL.path)

        XCTAssertEqual(preview, .text("hello\nworld\n"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }
}
