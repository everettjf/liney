import Foundation

/// Serial disk access keeps deletes ordered after pending writes.
nonisolated final class TerminalHistoryPersistence: @unchecked Sendable {
    static let paneLimit = 2 * 1024 * 1024
    static let totalLimit = 100 * 1024 * 1024
    private let directory: URL
    private let byteBudget: Int
    private let queue = DispatchQueue(label: "com.liney.terminal-history", qos: .utility)

    init(directory: URL = lineyStateDirectoryURL(fileManager: .default).appendingPathComponent("terminal-history", isDirectory: true), byteBudget: Int = totalLimit) {
        self.directory = directory
        self.byteBudget = byteBudget
    }

    static func boundedText(_ text: String, limit: Int = paneLimit) -> String {
        let bytes = Array(text.utf8.suffix(limit))
        guard let start = bytes.firstIndex(where: { $0 & 0xc0 != 0x80 }) else { return "" }
        return String(decoding: bytes[start...], as: UTF8.self)
    }

    func load(_ id: UUID) -> String? {
        queue.sync {
            let url = directory.appendingPathComponent(id.uuidString)
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size <= Self.paneLimit,
                  let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else { return nil }
            return text
        }
    }

    func save(_ text: String, for id: UUID) {
        let data = Data(Self.boundedText(text).utf8)
        queue.async { [self] in
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let url = directory.appendingPathComponent(id.uuidString)
                try data.write(to: url, options: [.atomic])
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                try enforceBudget()
            } catch {
                NSLog("Terminal history save failed: %@", error.localizedDescription)
            }
        }
    }

    func remove(_ ids: Set<UUID>) {
        queue.async { [self] in
            for id in ids { try? FileManager.default.removeItem(at: directory.appendingPathComponent(id.uuidString)) }
        }
    }

    func clear() {
        queue.sync { try? FileManager.default.removeItem(at: directory) }
    }

    func flush() { queue.sync {} }

    private func enforceBudget() throws {
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
        let entries = try urls.map { url in
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return (url: url, size: values.fileSize ?? 0, date: values.contentModificationDate ?? .distantPast)
        }.sorted { $0.date < $1.date }
        var total = entries.reduce(0) { $0 + $1.size }
        for entry in entries where total > byteBudget {
            try FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}

@MainActor
final class TerminalHistoryCoordinator {
    static let shared = TerminalHistoryCoordinator()
    private struct Entry {
        weak var session: ShellSession?
        var lastText: String?
    }
    private let persistence: TerminalHistoryPersistence
    private var entries: [UUID: Entry] = [:]
    private var timer: Timer?
    private var configured = false
    private(set) var enabled = false

    init(persistence: TerminalHistoryPersistence = TerminalHistoryPersistence()) {
        self.persistence = persistence
    }

    // Lifecycle cleanup is explicit in configure(enabled:); avoid the
    // Xcode 26 MainActor deinit back-deployment thunk on macOS 15.
    nonisolated deinit {}

    func configure(enabled: Bool) {
        guard !configured || self.enabled != enabled else { return }
        configured = true
        self.enabled = enabled
        timer?.invalidate()
        timer = nil
        if enabled {
            timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.captureAll() }
            }
        } else {
            for id in Array(entries.keys) {
                entries[id]?.session?.restoredHistory = nil
                entries[id]?.lastText = nil
            }
            persistence.clear()
        }
    }

    func register(_ session: ShellSession, restored: Bool) {
        entries[session.id] = Entry(session: session)
        if enabled, restored { session.restoredHistory = persistence.load(session.id) }
    }

    func capture(_ session: ShellSession) {
        guard enabled, entries[session.id]?.session === session,
              let text = session.readScreenText(scrollback: true), !text.isEmpty else { return }
        let bounded = TerminalHistoryPersistence.boundedText(text)
        guard entries[session.id]?.lastText != bounded else { return }
        entries[session.id]?.lastText = bounded
        persistence.save(bounded, for: session.id)
    }

    func discard(_ ids: Set<UUID>) {
        for id in ids {
            entries[id]?.session?.restoredHistory = nil
            entries.removeValue(forKey: id)
        }
        persistence.remove(ids)
    }

    func flush() {
        captureAll()
        persistence.flush()
    }

    private func captureAll() {
        for id in Array(entries.keys) {
            guard let session = entries[id]?.session else {
                entries.removeValue(forKey: id)
                continue
            }
            capture(session)
        }
    }
}
