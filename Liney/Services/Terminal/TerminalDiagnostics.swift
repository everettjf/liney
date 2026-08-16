//
//  TerminalDiagnostics.swift
//  Liney
//

import AppKit
import Combine
import Foundation
import SwiftUI

struct TerminalDiagnosticEntry: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let message: String

    init(id: UUID = UUID(), timestamp: Date = Date(), message: String) {
        self.id = id
        self.timestamp = timestamp
        self.message = message
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
}
