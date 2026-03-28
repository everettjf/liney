import XCTest
@testable import Liney

final class LightweightEditorSupportTests: XCTestCase {
    func testLoadAndSaveTextFileRoundTripsUTF8Contents() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = directoryURL.appendingPathComponent("config.env")

        try LightweightEditorSupport.saveTextFile(contents: "FOO=bar\nBAZ=qux\n", to: fileURL)
        let reloaded = try LightweightEditorSupport.loadTextFile(at: fileURL)

        XCTAssertEqual(reloaded, "FOO=bar\nBAZ=qux\n")
    }

    func testLoadTextFileRejectsBinaryData() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = directoryURL.appendingPathComponent("blob.bin")
        try Data([0xFF, 0xD8, 0xFF, 0x00]).write(to: fileURL)

        XCTAssertThrowsError(try LightweightEditorSupport.loadTextFile(at: fileURL))
    }
}
