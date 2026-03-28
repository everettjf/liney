//
//  LightweightEditorSupport.swift
//  Liney
//

import Foundation

enum LightweightEditorSupport {
    static func loadTextFile(at fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return text
    }

    static func saveTextFile(contents: String, to fileURL: URL) throws {
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
