import AppKit
import GhosttyKit
import XCTest
@testable import Liney

@MainActor
final class LineyGhosttyClipboardTests: XCTestCase {
    func testCompletionPreservesBinaryAndEmbeddedNullBytes() {
        let items = [
            LineyGhosttyClipboardPayload(mimeType: "text/plain", text: "你好\0tail"),
            LineyGhosttyClipboardPayload(mimeType: "application/octet-stream", data: Data([0, 255, 128, 0])),
        ]
        lineyGhosttyWithClipboardCompletion(items: items, available: ["text/plain"], confirmed: true) { pointer in
            let completion = pointer.pointee
            XCTAssertEqual(lineyGhosttyCopyClipboardContents(completion.contents, count: completion.contents_len), items)
            XCTAssertEqual(lineyGhosttyCopyClipboardMimes(completion.available, count: completion.available_len), ["text/plain"])
            XCTAssertTrue(completion.confirmed)
            XCTAssertFalse(completion.remember)
        }
    }

    func testBorrowedContentsAreCopiedBeforeStorageChanges() {
        let bytes = UnsafeMutablePointer<CChar>.allocate(capacity: 3)
        defer { bytes.deallocate() }
        bytes.initialize(repeating: 65, count: 3)
        let copied = "text/plain".withCString { mime in
            var content = ghostty_clipboard_content_s(mime: mime, data: UnsafePointer(bytes), len: 3)
            return withUnsafePointer(to: &content) {
                lineyGhosttyCopyClipboardContents($0, count: 1)
            }
        }
        bytes[0] = 66
        XCTAssertEqual(copied.first?.data, Data([65, 65, 65]))
    }

    func testEmptyRepresentationDoesNotRequireDataPointer() {
        "text/plain".withCString { mime in
            var content = ghostty_clipboard_content_s(mime: mime, data: nil, len: 0)
            let copied = withUnsafePointer(to: &content) { lineyGhosttyCopyClipboardContents($0, count: 1) }
            XCTAssertEqual(copied, [LineyGhosttyClipboardPayload(mimeType: "text/plain", data: Data())])
        }
    }

    func testListingCanCompleteWithoutContent() {
        lineyGhosttyWithClipboardCompletion(items: [], available: ["text/plain"], confirmed: false) { pointer in
            XCTAssertEqual(pointer.pointee.contents_len, 0)
            XCTAssertEqual(pointer.pointee.available_len, 1)
            XCTAssertFalse(pointer.pointee.confirmed)
        }
    }

    func testPasteboardWritePreservesRawDataAndUTF8Text() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("liney-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let binary = Data([255, 0, 128])
        lineyGhosttyWriteClipboard([
            LineyGhosttyClipboardPayload(mimeType: "text/plain;charset=utf-8", text: "你好"),
            LineyGhosttyClipboardPayload(mimeType: "application/octet-stream", data: binary),
        ], to: pasteboard)
        XCTAssertEqual(pasteboard.lineyGhosttyBestString, "你好")
        XCTAssertEqual(pasteboard.data(forType: NSPasteboard.PasteboardType("application/octet-stream")), binary)
    }
}
