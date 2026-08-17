//
//  TerminalDiagnostics.swift
//  Liney
//

import AppKit
import Combine
import Foundation
import GhosttyKit
import SwiftUI
import UniformTypeIdentifiers

struct TerminalDiagnosticContext: Equatable {
    var paneID: UUID?
    var sessionID: UUID?
    var surfaceID: String?

    var formattedPrefix: String {
        [
            paneID.map { "pane=\($0.uuidString.lowercased())" },
            sessionID.map { "session=\($0.uuidString.lowercased())" },
            surfaceID.map { "surface=\($0)" },
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }
}

struct TerminalDiagnosticEntry: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let message: String
    let context: TerminalDiagnosticContext?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        message: String,
        context: TerminalDiagnosticContext? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.message = message
        self.context = context
    }
}

struct TerminalDiagnosticLogStore {
    private(set) var entries: [TerminalDiagnosticEntry] = []
    let retentionInterval: TimeInterval
    let maximumEntryCount: Int

    init(retentionInterval: TimeInterval = 60 * 60, maximumEntryCount: Int = 5_000) {
        self.retentionInterval = retentionInterval
        self.maximumEntryCount = maximumEntryCount
    }

    mutating func append(_ entry: TerminalDiagnosticEntry, now: Date = Date()) {
        entries.append(entry)
        prune(now: now)
    }

    mutating func prune(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-retentionInterval)
        entries.removeAll { $0.timestamp < cutoff }
        if entries.count > maximumEntryCount {
            entries.removeFirst(entries.count - maximumEntryCount)
        }
    }

    mutating func removeAll() {
        entries.removeAll(keepingCapacity: true)
    }
}

struct TerminalDiagnosticReportMetadata: Equatable {
    let appVersion: String
    let appBuild: String
    let macOSVersion: String
    let architecture: String
    let ghosttyVersion: String

    static var current: Self {
        let info = ghostty_info()
        let ghosttyVersion: String
        if let pointer = info.version, info.version_len > 0 {
            let bytes = UnsafeRawPointer(pointer).assumingMemoryBound(to: UInt8.self)
            ghosttyVersion = String(decoding: UnsafeBufferPointer(start: bytes, count: Int(info.version_len)), as: UTF8.self)
        } else {
            ghosttyVersion = "unknown"
        }
#if arch(arm64)
        let architecture = "arm64"
#elseif arch(x86_64)
        let architecture = "x86_64"
#else
        let architecture = "unknown"
#endif
        return Self(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: architecture,
            ghosttyVersion: ghosttyVersion
        )
    }
}

func terminalDiagnosticReport(metadata: TerminalDiagnosticReportMetadata, log: String) -> String {
    """
    Liney Terminal Diagnostics
    Liney: \(metadata.appVersion) (\(metadata.appBuild))
    macOS: \(metadata.macOSVersion)
    Architecture: \(metadata.architecture)
    Ghostty: \(metadata.ghosttyVersion)

    Recent events (maximum one hour; terminal input is not recorded):
    \(log.isEmpty ? "(none)" : log)
    """
}

func terminalDiagnosticIssueURL(
    metadata: TerminalDiagnosticReportMetadata,
    attachmentName: String
) -> URL? {
    var components = URLComponents(string: "https://github.com/everettjf/liney/issues/new")
    let body = """
    ## Terminal problem

    Describe what happened and what you expected.

    ## Environment

    - Liney: \(metadata.appVersion) (\(metadata.appBuild))
    - macOS: \(metadata.macOSVersion)
    - Architecture: \(metadata.architecture)
    - Ghostty: \(metadata.ghosttyVersion)

    ## Diagnostics

    Please drag `\(attachmentName)` from the Finder window into this issue.
    The file contains lifecycle and rendering events only; terminal input is not recorded.
    """
    components?.queryItems = [
        URLQueryItem(name: "title", value: "Terminal: "),
        URLQueryItem(name: "labels", value: "terminal"),
        URLQueryItem(name: "body", value: body),
    ]
    return components?.url
}

func writeTerminalDiagnosticAttachment(
    report: String,
    directory: URL = FileManager.default.temporaryDirectory
) throws -> URL {
    let folder = directory.appendingPathComponent("Liney-Terminal-Diagnostics", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let suffix = String(UUID().uuidString.prefix(8)).lowercased()
    let url = folder.appendingPathComponent(
        "Liney-Terminal-Diagnostics-\(formatter.string(from: Date()))-\(suffix).log"
    )
    try report.write(to: url, atomically: true, encoding: .utf8)
    return url
}

@MainActor
final class TerminalDiagnostics: ObservableObject {
    static let shared = TerminalDiagnostics()

    @Published private(set) var entries: [TerminalDiagnosticEntry] = []
    private var store = TerminalDiagnosticLogStore()

    private init() {}

    func record(_ message: String, timestamp: Date = Date()) {
        store.append(TerminalDiagnosticEntry(timestamp: timestamp, message: message), now: timestamp)
        entries = store.entries
    }

    func record(
        event: String,
        context: TerminalDiagnosticContext? = nil,
        attributes: [String: String] = [:],
        timestamp: Date = Date()
    ) {
        let prefix = context?.formattedPrefix ?? ""
        let suffix = attributes.keys.sorted().map { key in
            "\(key)=\(attributes[key] ?? "")"
        }
        .joined(separator: " ")
        let message = [prefix, "event=\(event)", suffix]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        store.append(
            TerminalDiagnosticEntry(timestamp: timestamp, message: message, context: context),
            now: timestamp
        )
        entries = store.entries
    }

    func clear() {
        store.removeAll()
        entries = []
    }

    func pruneExpired(now: Date = Date()) {
        store.prune(now: now)
        entries = store.entries
    }

    var formattedLog: String {
        let formatter = Self.timestampFormatter
        return entries.map { entry in
            "[\(formatter.string(from: entry.timestamp))] \(entry.message)"
        }
        .joined(separator: "\n")
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
}

@MainActor
final class TerminalDiagnosticsWindowManager: NSObject, NSWindowDelegate {
    static let shared = TerminalDiagnosticsWindowManager()

    private var window: NSWindow?

    private override init() {}

    func show() {
        TerminalDiagnostics.shared.pruneExpired()
        if let window {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = TerminalDiagnosticsView(diagnostics: .shared)
            .preferredColorScheme(.dark)
        let hostingController = NSHostingController(rootView: contentView)
        hostingController.sizingOptions = []

        let window = NSWindow(contentViewController: hostingController)
        window.title = LocalizationManager.shared.string("terminalDiagnostics.title")
        window.identifier = NSUserInterfaceItemIdentifier("liney.terminalDiagnostics")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 700, height: 420)
        window.setFrameAutosaveName("LineyTerminalDiagnosticsWindow")
        if UserDefaults.standard.string(forKey: "NSWindow Frame LineyTerminalDiagnosticsWindow") == nil {
            window.setContentSize(NSSize(width: 980, height: 640))
            window.center()
        }
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

private struct TerminalDiagnosticsView: View {
    @ObservedObject var diagnostics: TerminalDiagnostics

    private func localized(_ key: String) -> String {
        LocalizationManager.shared.string(key)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(localized("terminalDiagnostics.title"))
                        .font(.headline)
                    Text(localized("terminalDiagnostics.retentionHint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(diagnostics.entries.count)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button(localized("terminalDiagnostics.copy")) {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(diagnostics.formattedLog, forType: .string)
                }
                .disabled(diagnostics.entries.isEmpty)
                Button(localized("terminalDiagnostics.export")) {
                    exportReport()
                }
                Button(localized("terminalDiagnostics.reportIssue")) {
                    reportIssue()
                }
                Button(localized("terminalDiagnostics.clear"), role: .destructive) {
                    diagnostics.clear()
                }
                .disabled(diagnostics.entries.isEmpty)
            }
            .padding(12)

            Divider()

            ScrollView {
                Text(diagnostics.formattedLog.isEmpty ? localized("terminalDiagnostics.empty") : diagnostics.formattedLog)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
            }
        }
    }

    private func exportReport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Liney-Terminal-Diagnostics.log"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let report = terminalDiagnosticReport(metadata: .current, log: diagnostics.formattedLog)
            try report.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    private func reportIssue() {
        do {
            let metadata = TerminalDiagnosticReportMetadata.current
            let report = terminalDiagnosticReport(metadata: metadata, log: diagnostics.formattedLog)
            let attachmentURL = try writeTerminalDiagnosticAttachment(report: report)
            guard let issueURL = terminalDiagnosticIssueURL(
                metadata: metadata,
                attachmentName: attachmentURL.lastPathComponent
            ) else { return }
            NSWorkspace.shared.open(issueURL)
            NSWorkspace.shared.activateFileViewerSelecting([attachmentURL])
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
