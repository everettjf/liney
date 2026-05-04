//
//  LineyControlClient.swift
//  Liney
//
//  Author: everettjf
//

import Darwin
import Foundation

/// Synchronous Unix-domain socket client for the multi-command control
/// protocol. Reads back a single newline-terminated JSON response.
enum LineyControlClient {
    /// Sends a control frame and reads the JSON response. Returns nil
    /// for fire-and-forget commands (the server simply closes the
    /// connection without writing a response).
    static func send(
        frame: Data,
        socketURL: URL = AgentNotifySocketPath.resolveSocketURL(),
        timeout: TimeInterval = 5.0
    ) throws -> LineyControlResponse? {
        let socketPath = socketURL.path
        guard !socketPath.isEmpty else {
            throw AgentNotifyError.socketUnavailable
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw AgentNotifyError.socketUnavailable
        }
        defer { close(fd) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count <= pathCapacity else {
            throw AgentNotifyError.socketUnavailable
        }
        withUnsafeMutablePointer(to: &address.sun_path) { tuplePointer in
            tuplePointer.withMemoryRebound(to: CChar.self, capacity: pathCapacity) { dest in
                pathBytes.withUnsafeBufferPointer { source in
                    if let base = source.baseAddress {
                        dest.update(from: base, count: pathBytes.count)
                    }
                }
            }
        }

        var ioTimeout = timeval(
            tv_sec: Int(timeout),
            tv_usec: Int32((timeout - Double(Int(timeout))) * 1_000_000)
        )
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &ioTimeout, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &ioTimeout, socklen_t(MemoryLayout<timeval>.size))

        let connectResult = withUnsafePointer(to: &address) { addrPointer -> Int32 in
            addrPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if connectResult != 0 {
            throw AgentNotifyError.socketUnavailable
        }

        var written = 0
        try frame.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            while written < frame.count {
                let remaining = frame.count - written
                let n = Darwin.write(fd, base.advanced(by: written), remaining)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw AgentNotifyError.socketWriteFailed(errno: errno)
                }
                if n == 0 { break }
                written += n
            }
        }

        // Half-close write so the server sees EOF and writes its response.
        shutdown(fd, SHUT_WR)

        var collected = Data()
        let chunkSize = 4096
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        let maxResponseBytes = AgentNotifyProtocol.maxFrameBytes
        while collected.count < maxResponseBytes {
            let n = buffer.withUnsafeMutableBufferPointer { ptr -> Int in
                Darwin.read(fd, ptr.baseAddress, chunkSize)
            }
            if n < 0 {
                if errno == EINTR { continue }
                break
            }
            if n == 0 { break }
            collected.append(contentsOf: buffer.prefix(n))
            if buffer.prefix(n).contains(0x0A) { break }
        }

        if collected.isEmpty { return nil }

        let trimmed = collected.last == 0x0A ? collected.dropLast() : collected
        if let lineEnd = trimmed.firstIndex(of: 0x0A) {
            return try? JSONDecoder().decode(LineyControlResponse.self, from: trimmed.prefix(upTo: lineEnd))
        }
        return try? JSONDecoder().decode(LineyControlResponse.self, from: trimmed)
    }
}
