//
//  AgentNotifyClient.swift
//  Liney
//
//  Author: everettjf
//

import Darwin
import Foundation

/// Synchronous Unix-domain socket client used by the `liney notify` CLI to
/// hand a single notification frame to the running app.
///
/// Blocking by design: the CLI process is short-lived, fires one request, and
/// exits. No reconnection or retry beyond a single connect attempt — if the
/// app is not running the caller is told so the user can react.
enum AgentNotifyClient {
    /// Sends a single notification frame to the running Liney app.
    /// Throws `AgentNotifyError.socketUnavailable` if the app is not listening.
    static func send(
        _ request: AgentNotifyRequest,
        socketURL: URL = AgentNotifySocketPath.resolveSocketURL(),
        timeout: TimeInterval = 2.0
    ) throws {
        let frame = try AgentNotifyProtocol.encode(request)

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

        // SO_SNDTIMEO so a stalled server can't pin the CLI forever.
        var sendTimeout = timeval(
            tv_sec: Int(timeout),
            tv_usec: Int32((timeout - Double(Int(timeout))) * 1_000_000)
        )
        _ = setsockopt(
            fd,
            SOL_SOCKET,
            SO_SNDTIMEO,
            &sendTimeout,
            socklen_t(MemoryLayout<timeval>.size)
        )

        let connectResult = withUnsafePointer(to: &address) { addrPointer -> Int32 in
            addrPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if connectResult != 0 {
            throw AgentNotifyError.socketUnavailable
        }

        var bytesWritten = 0
        try frame.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) in
            guard let base = rawBuffer.baseAddress else { return }
            while bytesWritten < frame.count {
                let remaining = frame.count - bytesWritten
                let written = Darwin.write(fd, base.advanced(by: bytesWritten), remaining)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw AgentNotifyError.socketWriteFailed(errno: errno)
                }
                if written == 0 { break }
                bytesWritten += written
            }
        }
    }
}
