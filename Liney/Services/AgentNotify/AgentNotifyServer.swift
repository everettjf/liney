//
//  AgentNotifyServer.swift
//  Liney
//
//  Author: everettjf
//

import Darwin
import Dispatch
import Foundation

/// Unix-domain socket server that accepts notification frames sent by
/// `liney notify` and dispatches them to a handler on the main actor.
///
/// One frame per connection, no response. The server tolerates partial reads
/// and rejects oversized payloads to keep the surface small.
final class AgentNotifyServer {
    typealias Handler = @MainActor (AgentNotifyRequest) -> Void

    private let socketURL: URL
    private let handler: Handler
    private let queue = DispatchQueue(label: "dev.liney.agent-notify.server", qos: .utility)
    private var listenSocket: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var isRunning = false

    init(
        socketURL: URL = AgentNotifySocketPath.resolveSocketURL(),
        handler: @escaping Handler
    ) {
        self.socketURL = socketURL
        self.handler = handler
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

        queue.async { [handler] in
            defer { close(clientFD) }

            // Cap the read size to refuse overly large payloads early.
            let limit = AgentNotifyProtocol.maxFrameBytes
            var readTimeout = timeval(tv_sec: 2, tv_usec: 0)
            _ = setsockopt(
                clientFD,
                SOL_SOCKET,
                SO_RCVTIMEO,
                &readTimeout,
                socklen_t(MemoryLayout<timeval>.size)
            )

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

            // Use only the first frame (up to and including \n if present).
            let frameRange: Range<Data.Index>
            if let newlineIndex = collected.firstIndex(of: 0x0A) {
                frameRange = collected.startIndex..<collected.index(after: newlineIndex)
            } else {
                frameRange = collected.startIndex..<collected.endIndex
            }
            let frame = collected.subdata(in: frameRange)

            let request: AgentNotifyRequest
            do {
                request = try AgentNotifyProtocol.decode(frame)
            } catch {
                return
            }

            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    handler(request)
                }
            }
        }
    }
}
