//
//  AgentNotifyServer.swift
//  Liney
//
//  Author: everettjf
//

import Darwin
import Dispatch
import Foundation

/// Unix-domain socket server used by the `liney` CLI to talk to the running
/// app. One frame per connection. The handler can return a response frame
/// (also one JSON line) which is written back before the connection is
/// closed; returning `nil` makes the request fire-and-forget.
///
/// The handler runs on the server's dispatch queue. Callers that need to
/// touch main-actor state hop themselves (production wiring uses a synchronous
/// `DispatchQueue.main.async` + semaphore bridge so the response can be
/// computed on the main actor before the server writes it back).
final class AgentNotifyServer {
    typealias FrameHandler = @Sendable (Data) -> Data?

    private let socketURL: URL
    private let handler: FrameHandler
    private let queue = DispatchQueue(label: "dev.liney.agent-notify.server", qos: .utility)
    private var listenSocket: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var isRunning = false

    init(
        socketURL: URL = AgentNotifySocketPath.resolveSocketURL(),
        handler: @escaping FrameHandler
    ) {
        self.socketURL = socketURL
        self.handler = handler
    }

    /// Convenience for the legacy notify-only path: wraps a synchronous
    /// `AgentNotifyRequest` handler that does not produce a response.
    ///
    /// `notifyHandler` is required to be `@Sendable` so it can be captured
    /// into the underlying `@Sendable` frame handler. Swift hops to the
    /// main actor inside the dispatched `Task`, satisfying the
    /// `@MainActor` requirement at the call site.
    convenience init(
        socketURL: URL = AgentNotifySocketPath.resolveSocketURL(),
        notifyHandler: @escaping @Sendable @MainActor (AgentNotifyRequest) -> Void
    ) {
        self.init(socketURL: socketURL) { data in
            guard let request = try? AgentNotifyProtocol.decode(data) else { return nil }
            Task { @MainActor in
                notifyHandler(request)
            }
            return nil
        }
    }

    deinit {
        stop()
    }

    func start() throws {
        guard !isRunning else { return }

        try AgentNotifySocketPath.ensureDirectory()

        let socketPath = socketURL.path
        let pathCapacity = MemoryLayout.size(ofValue: sockaddr_un().sun_path)
        guard socketPath.utf8CString.count <= pathCapacity else {
            throw AgentNotifyError.socketUnavailable
        }

        // Stale socket files from a previous (crashed) run block bind. If the
        // path exists and nobody is listening on the other side, remove it.
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw AgentNotifyError.socketUnavailable
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &address.sun_path) { tuplePointer in
            tuplePointer.withMemoryRebound(to: CChar.self, capacity: pathCapacity) { dest in
                pathBytes.withUnsafeBufferPointer { source in
                    if let base = source.baseAddress {
                        dest.update(from: base, count: pathBytes.count)
                    }
                }
            }
        }

        let bindResult = withUnsafePointer(to: &address) { addrPointer -> Int32 in
            addrPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if bindResult != 0 {
            close(fd)
            throw AgentNotifyError.socketUnavailable
        }

        // Owner-only access; the socket sits under the user's home but tighten
        // explicitly anyway.
        chmod(socketPath, S_IRUSR | S_IWUSR)

        if listen(fd, 16) != 0 {
            close(fd)
            unlink(socketPath)
            throw AgentNotifyError.socketUnavailable
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptOnce()
        }
        source.setCancelHandler { [fd] in
            close(fd)
        }

        listenSocket = fd
        acceptSource = source
        isRunning = true
        source.resume()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        acceptSource?.cancel()
        acceptSource = nil
        if listenSocket >= 0 {
            // Cancel handler closes the fd; just clear the reference.
            listenSocket = -1
        }
        unlink(socketURL.path)
    }

    private func acceptOnce() {
        guard listenSocket >= 0 else { return }
        let clientFD = accept(listenSocket, nil, nil)
        if clientFD < 0 {
            return
        }

        let handler = self.handler
        queue.async {
            defer { close(clientFD) }

            var readTimeout = timeval(tv_sec: 2, tv_usec: 0)
            _ = setsockopt(
                clientFD,
                SOL_SOCKET,
                SO_RCVTIMEO,
                &readTimeout,
                socklen_t(MemoryLayout<timeval>.size)
            )

            let limit = AgentNotifyProtocol.maxFrameBytes
            var collected = Data()
            collected.reserveCapacity(min(limit, 4096))
            let chunkSize = 4096
            var buffer = [UInt8](repeating: 0, count: chunkSize)

            while collected.count < limit {
                let read = buffer.withUnsafeMutableBufferPointer { ptr -> Int in
                    Darwin.read(clientFD, ptr.baseAddress, chunkSize)
                }
                if read < 0 {
                    if errno == EINTR { continue }
                    return
                }
                if read == 0 { break } // peer closed
                collected.append(contentsOf: buffer.prefix(read))
                if buffer.prefix(read).contains(0x0A) { break }
            }

            guard !collected.isEmpty else { return }

            let frameRange: Range<Data.Index>
            if let newlineIndex = collected.firstIndex(of: 0x0A) {
                frameRange = collected.startIndex..<collected.index(after: newlineIndex)
            } else {
                frameRange = collected.startIndex..<collected.endIndex
            }
            let frame = collected.subdata(in: frameRange)

            // Synchronous handler call on the server queue. Caller is
            // responsible for any cross-actor hopping.
            let response = handler(frame)
            if let response {
                var bytes = response
                if bytes.last != 0x0A { bytes.append(0x0A) }
                var written = 0
                bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                    guard let base = raw.baseAddress else { return }
                    while written < bytes.count {
                        let n = Darwin.write(clientFD, base.advanced(by: written), bytes.count - written)
                        if n <= 0 { break }
                        written += n
                    }
                }
            }
        }
    }
}

/// Bridges the synchronous server-queue frame handler to the @MainActor
/// dispatcher. Synchronous on purpose: callers writing a response need
/// the value before the connection closes.
enum AgentNotifyMainActorBridge {
    static func dispatchOnMain(_ frame: Data, dispatcher: LineyControlDispatcher) -> Data? {
        let captureBox = AgentNotifyResponseBox()
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                captureBox.value = dispatcher.dispatch(frame: frame)
            }
            semaphore.signal()
        }
        // Bound the wait so a stuck main thread can't pin the server queue
        // forever — under load, the timeout simply produces a no-response
        // close, which the CLI surfaces as an I/O error.
        _ = semaphore.wait(timeout: .now() + 5)
        return captureBox.value
    }
}

/// One-slot box for shuttling the response across the dispatch boundary.
/// Mutated only on the main thread, read only after the semaphore signals,
/// so no locking is needed.
private final class AgentNotifyResponseBox: @unchecked Sendable {
    var value: Data?
}
