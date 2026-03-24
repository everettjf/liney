//
//  LineyGhosttyBootstrap.swift
//  Liney
//
//  Author: everettjf
//

import Foundation
import GhosttyKit

enum LineyGhosttyBootstrap {
    private static let initialized: Void = {
        LineyGhosttyLogFilter.installIfNeeded()
        applyProcessEnvironment()
        let result = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
        guard result == GHOSTTY_SUCCESS else {
            let message = """
            libghostty initialization failed before the app launched.
            This usually means the embedded Ghostty runtime could not initialize its global state.
            """
            FileHandle.standardError.write(Data(message.utf8))
            exit(1)
        }
    }()

    static func initialize() {
        _ = initialized
    }

    static func processEnvironment(
        resourcePaths: LineyGhosttyResourcePaths = .bundleMain()
    ) -> [String: String] {
        guard let ghosttyResourcesDirectory = resourcePaths.ghosttyResourcesDirectory else {
            return [:]
        }
        return ["GHOSTTY_RESOURCES_DIR": ghosttyResourcesDirectory]
    }

    private static func applyProcessEnvironment(
        resourcePaths: LineyGhosttyResourcePaths = .bundleMain()
    ) {
        for (key, value) in processEnvironment(resourcePaths: resourcePaths) {
            setenv(key, value, 1)
        }
    }
}

enum LineyGhosttyLogFilter {
    private static let suppressedFragments = [
        "io_thread: mailbox message=start_synchronized_output",
        "debug(io_thread): mailbox message=start_synchronized_output",
    ]

    private static var isInstalled = false
    private static var stderrFilter: StreamFilter?
    private static var stdoutFilter: StreamFilter?

    static func installIfNeeded() {
        guard !isInstalled else { return }
        isInstalled = true
        stderrFilter = StreamFilter(fileDescriptor: STDERR_FILENO)
        stdoutFilter = StreamFilter(fileDescriptor: STDOUT_FILENO)
    }

    static func shouldSuppress(_ line: String) -> Bool {
        suppressedFragments.contains { line.contains($0) }
    }

    private final class StreamFilter {
        private let readHandle: FileHandle
        private let passthroughHandle: FileHandle
        private var buffer = Data()

        init?(fileDescriptor: Int32) {
            let pipe = Pipe()
            let duplicatedDescriptor = dup(fileDescriptor)
            guard duplicatedDescriptor >= 0 else { return nil }

            readHandle = pipe.fileHandleForReading
            passthroughHandle = FileHandle(fileDescriptor: duplicatedDescriptor, closeOnDealloc: true)

            dup2(pipe.fileHandleForWriting.fileDescriptor, fileDescriptor)
            pipe.fileHandleForWriting.closeFile()

            readHandle.readabilityHandler = { [weak self] handle in
                self?.consume(handle.availableData)
            }
        }

        private func consume(_ data: Data) {
            guard !data.isEmpty else {
                flushRemainingBuffer()
                return
            }

            buffer.append(data)

            while let newlineRange = buffer.firstRange(of: Data([0x0A])) {
                let lineData = buffer.subdata(in: 0..<newlineRange.upperBound)
                buffer.removeSubrange(0..<newlineRange.upperBound)
                forward(lineData)
            }
        }

        private func flushRemainingBuffer() {
            guard !buffer.isEmpty else { return }
            forward(buffer)
            buffer.removeAll(keepingCapacity: false)
        }

        private func forward(_ data: Data) {
            let line = String(data: data, encoding: .utf8) ?? ""
            guard !LineyGhosttyLogFilter.shouldSuppress(line) else { return }
            try? passthroughHandle.write(contentsOf: data)
        }
    }
}
