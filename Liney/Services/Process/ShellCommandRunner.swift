//
//  ShellCommandRunner.swift
//  Liney
//
//  Author: everettjf
//

import Darwin
import Foundation
import os

nonisolated struct ShellCommandResult {
    var stdout: String
    var stderr: String
    var exitCode: Int32
}

nonisolated enum ShellCommandError: LocalizedError {
    case executableNotFound(String)
    case failed(String)
    case timedOut(TimeInterval)

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let executable):
            return "Executable not found: \(executable)"
        case .failed(let message):
            return message
        case .timedOut(let seconds):
            return "Command timed out after \(Int(seconds)) seconds"
        }
    }

    var isTimeout: Bool {
        if case .timedOut = self { return true }
        return false
    }
}

actor ShellCommandRunner {
    func run(
        executable: String,
        arguments: [String],
        currentDirectory: String? = nil,
        environment: [String: String]? = nil
    ) async throws -> ShellCommandResult {
        try await run(
            executable: executable,
            arguments: arguments,
            currentDirectory: currentDirectory,
            environment: environment,
            processHandle: nil
        )
    }

    func run(
        executable: String,
        arguments: [String],
        currentDirectory: String? = nil,
        environment: [String: String]? = nil,
        timeout: TimeInterval
    ) async throws -> ShellCommandResult {
        let commandDescription = ([executable] + arguments).joined(separator: " ")
        let processHandle = ProcessHandle()
        do {
            return try await withTaskCancellationHandler {
                try await withThrowingTaskGroup(of: ShellCommandResult.self) { group in
                    group.addTask {
                        try await withTaskCancellationHandler {
                            try await self.run(
                                executable: executable,
                                arguments: arguments,
                                currentDirectory: currentDirectory,
                                environment: environment,
                                processHandle: processHandle
                            )
                        } onCancel: {
                            processHandle.terminate()
                        }
                    }
                    group.addTask {
                        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                        throw ShellCommandError.timedOut(timeout)
                    }
                    let result = try await group.next()!
                    group.cancelAll()
                    return result
                }
            } onCancel: {
                processHandle.terminate()
            }
        } catch let error as ShellCommandError where error.isTimeout {
            // Terminate the orphaned child process so it doesn't linger.
            processHandle.terminate()
            if AppLogger.isEnabled { AppLogger.shell.error("Command timed out after \(Int(timeout))s: \(commandDescription, privacy: .public)") }
            throw error
        }
    }

    private func run(
        executable: String,
        arguments: [String],
        currentDirectory: String?,
        environment: [String: String]?,
        processHandle: ProcessHandle?
    ) async throws -> ShellCommandResult {
        let isAbsolutePath = executable.contains("/")
        guard !isAbsolutePath || FileManager.default.isExecutableFile(atPath: executable) else {
            if AppLogger.isEnabled { AppLogger.shell.error("Executable not found: \(executable, privacy: .public)") }
            throw ShellCommandError.executableNotFound(executable)
        }

        let commandDescription = ([executable] + arguments).joined(separator: " ")
        if AppLogger.isVerbose { AppLogger.shell.debug("Running: \(commandDescription, privacy: .public) in \(currentDirectory ?? "(default)", privacy: .public)") }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
        }
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Concurrently drain pipes to avoid deadlock on large output. Large
        // stdout/stderr can fill the pipe buffer, blocking the child process
        // from exiting — if we only read after terminationHandler fires, we
        // can deadlock forever.
        let stdoutBuffer = PipeBuffer()
        let stderrBuffer = PipeBuffer()
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            if !stdoutBuffer.consumeAvailableData(from: handle) {
                handle.readabilityHandler = nil
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            if !stderrBuffer.consumeAvailableData(from: handle) {
                handle.readabilityHandler = nil
            }
        }

        let result: ShellCommandResult = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                // Disable future callbacks, then serialize the final read with
                // any callback already in flight. Otherwise a short-lived
                // command can exit after its handler reads stderr but before
                // that handler appends the bytes to our buffer.
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                let stdout = stdoutBuffer.finishReading(from: stdoutPipe.fileHandleForReading)
                let stderr = stderrBuffer.finishReading(from: stderrPipe.fileHandleForReading)
                continuation.resume(
                    returning: ShellCommandResult(
                        stdout: String(decoding: stdout, as: UTF8.self),
                        stderr: String(decoding: stderr, as: UTF8.self),
                        exitCode: process.terminationStatus
                    )
                )
            }

            do {
                try process.run()
                processHandle?.set(process)
            } catch {
                if AppLogger.isEnabled { AppLogger.shell.error("Failed to launch process: \(error.localizedDescription, privacy: .public)") }
                continuation.resume(throwing: ShellCommandError.failed(error.localizedDescription))
            }
        }

        if result.exitCode != 0, AppLogger.isEnabled {
            AppLogger.shell.warning("Command exited with code \(result.exitCode): \(commandDescription, privacy: .public)")
            if !result.stderr.isEmpty {
                AppLogger.shell.warning("stderr: \(result.stderr.prefix(500), privacy: .public)")
            }
        }

        return result
    }
}

/// Thread-safe holder for a running Process so the timeout path can terminate
/// it when cancellation fires.
nonisolated private final class ProcessHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var terminationRequested = false

    func set(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldTerminate = terminationRequested
        lock.unlock()
        if shouldTerminate {
            terminate(process)
        }
    }

    func terminate() {
        lock.lock()
        terminationRequested = true
        let process = self.process
        lock.unlock()
        guard let process, process.isRunning else { return }
        terminate(process)
    }

    private func terminate(_ process: Process) {
        process.terminate()

        // Some tools ignore SIGTERM. Escalate after a short grace period so a
        // timeout or task cancellation cannot leave the task group waiting for
        // an uncooperative child forever.
        let pid = process.processIdentifier
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .milliseconds(250)) {
            guard process.isRunning else { return }
            Darwin.kill(pid, SIGKILL)
        }
    }
}

/// Thread-safe accumulator for pipe data drained from a concurrent readability
/// handler.
nonisolated private final class PipeBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    /// Returns false after EOF.
    func consumeAvailableData(from handle: FileHandle) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let data = handle.availableData
        guard !data.isEmpty else { return false }
        buffer.append(data)
        return true
    }

    func finishReading(from handle: FileHandle) -> Data {
        lock.lock()
        defer { lock.unlock() }
        if let remaining = try? handle.readToEnd(), !remaining.isEmpty {
            buffer.append(remaining)
        }
        return buffer
    }
}
