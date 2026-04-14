//
//  ShellCommandRunner.swift
//  Liney
//
//  Author: everettjf
//

import Foundation
import os

struct ShellCommandResult {
    var stdout: String
    var stderr: String
    var exitCode: Int32
}

enum ShellCommandError: LocalizedError {
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
            return try await withThrowingTaskGroup(of: ShellCommandResult.self) { group in
                group.addTask {
                    try await self.run(
                        executable: executable,
                        arguments: arguments,
                        currentDirectory: currentDirectory,
                        environment: environment,
                        processHandle: processHandle
                    )
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw ShellCommandError.timedOut(timeout)
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
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
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                stdoutBuffer.append(data)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                stderrBuffer.append(data)
            }
        }

        let result: ShellCommandResult = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                // Flush any remaining data from the pipes. The readability
                // handler is called on a background queue, so drain
                // synchronously here to catch anything still buffered.
                let remainingStdout = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
                let remainingStderr = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                if !remainingStdout.isEmpty { stdoutBuffer.append(remainingStdout) }
                if !remainingStderr.isEmpty { stderrBuffer.append(remainingStderr) }
                continuation.resume(
                    returning: ShellCommandResult(
                        stdout: String(decoding: stdoutBuffer.data, as: UTF8.self),
                        stderr: String(decoding: stderrBuffer.data, as: UTF8.self),
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
private final class ProcessHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    func set(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        self.process = process
    }

    func terminate() {
        lock.lock()
        let process = self.process
        lock.unlock()
        guard let process, process.isRunning else { return }
        process.terminate()
    }
}

/// Thread-safe accumulator for pipe data drained from a concurrent readability
/// handler.
private final class PipeBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}
