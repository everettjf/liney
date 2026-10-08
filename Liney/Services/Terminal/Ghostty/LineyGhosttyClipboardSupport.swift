//
//  LineyGhosttyClipboardSupport.swift
//  Liney
//
//  Author: everettjf
//

import AppKit
import Foundation
import GhosttyKit

@MainActor
func lineyGhosttyPasteboard(for location: ghostty_clipboard_e) -> NSPasteboard? {
    switch location {
    case GHOSTTY_CLIPBOARD_STANDARD:
        return .general
    case GHOSTTY_CLIPBOARD_SELECTION:
        return NSPasteboard(name: NSPasteboard.Name("com.liney.selection"))
    default:
        return nil
    }
}

struct LineyGhosttyClipboardPayload: Sendable, Equatable {
    let mimeType: String
    let data: Data

    nonisolated init(mimeType: String, text: String) {
        self.mimeType = mimeType
        self.data = Data(text.utf8)
    }

    nonisolated init(mimeType: String, data: Data) {
        self.mimeType = mimeType
        self.data = data
    }

    nonisolated var text: String { String(decoding: data, as: UTF8.self) }

    nonisolated var isPlainText: Bool {
        mimeType == "text/plain"
            || mimeType == "text/plain;charset=utf-8"
            || mimeType == "public.utf8-plain-text"
            || mimeType == NSPasteboard.PasteboardType.string.rawValue
    }

    nonisolated var pasteboardType: NSPasteboard.PasteboardType? {
        if isPlainText {
            return .string
        }
        return NSPasteboard.PasteboardType(rawValue: mimeType)
    }
}

@MainActor
func lineyGhosttyWriteClipboard(_ items: [LineyGhosttyClipboardPayload], to pasteboard: NSPasteboard) {
    let supportedTypes = items.compactMap(\.pasteboardType)
    guard !supportedTypes.isEmpty else { return }

    pasteboard.clearContents()
    pasteboard.declareTypes(supportedTypes, owner: nil)
    for item in items {
        guard let type = item.pasteboardType else { continue }
        pasteboard.setData(item.data, forType: type)
    }
}

extension NSPasteboard {
    var lineyGhosttyBestString: String? {
        string(forType: .string)
            ?? string(forType: NSPasteboard.PasteboardType("public.utf8-plain-text"))
    }
}

// Callback buffers are borrowed and may not be null-terminated. Copy before
// dispatching to the main queue or presenting a permission prompt.
nonisolated func lineyGhosttyCopyClipboardContents(
    _ contents: UnsafePointer<ghostty_clipboard_content_s>?, count: Int
) -> [LineyGhosttyClipboardPayload] {
    guard let contents, count > 0 else { return [] }
    return (0..<count).compactMap { index in
        let entry = contents[index]
        guard let mime = entry.mime, entry.len == 0 || entry.data != nil else { return nil }
        let data = entry.len == 0 ? Data() : Data(bytes: entry.data!, count: entry.len)
        return LineyGhosttyClipboardPayload(mimeType: String(cString: mime), data: data)
    }
}

nonisolated func lineyGhosttyCopyClipboardMimes(
    _ mimes: UnsafePointer<UnsafePointer<CChar>?>?, count: Int
) -> [String] {
    guard let mimes, count > 0 else { return [] }
    return (0..<count).compactMap { mimes[$0].map { String(cString: $0) } }
}

@MainActor
func lineyGhosttyWithClipboardCompletion<T>(
    items: [LineyGhosttyClipboardPayload], available: [String], confirmed: Bool,
    _ body: (UnsafePointer<ghostty_clipboard_complete_s>) -> T
) -> T {
    var strings: [UnsafeMutablePointer<CChar>] = []
    var buffers: [UnsafeMutableRawPointer] = []
    defer {
        strings.forEach { free($0) }
        buffers.forEach { $0.deallocate() }
    }
    let contents: [ghostty_clipboard_content_s] = items.map { item in
        let mime = strdup(item.mimeType)!
        strings.append(mime)
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: max(item.data.count, 1), alignment: 1)
        buffers.append(buffer)
        item.data.withUnsafeBytes { bytes in
            if let base = bytes.baseAddress { buffer.copyMemory(from: base, byteCount: bytes.count) }
        }
        return ghostty_clipboard_content_s(
            mime: UnsafePointer(mime), data: UnsafePointer(buffer.assumingMemoryBound(to: CChar.self)),
            len: item.data.count
        )
    }
    let availableMimes: [UnsafePointer<CChar>?] = available.map { value in
        let string = strdup(value)!
        strings.append(string)
        return UnsafePointer(string)
    }
    return contents.withUnsafeBufferPointer { contents in
        availableMimes.withUnsafeBufferPointer { available in
            var complete = ghostty_clipboard_complete_s(
                contents: contents.baseAddress, contents_len: contents.count,
                available: available.baseAddress, available_len: available.count,
                confirmed: confirmed, remember: false
            )
            return withUnsafePointer(to: &complete, body)
        }
    }
}
