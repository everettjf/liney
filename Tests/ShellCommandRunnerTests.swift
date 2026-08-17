//
//  ShellCommandRunnerTests.swift
//  LineyTests
//

import XCTest
@testable import Liney

final class ShellCommandRunnerTests: XCTestCase {
    func testRunCapturesLargeStandardOutputAndError() async throws {
        let result = try await ShellCommandRunner().run(
            executable: "/bin/zsh",
            arguments: ["-c", "i=0; while [ $i -lt 3000 ]; do echo stdout-$i; echo stderr-$i >&2; i=$((i+1)); done"],
            timeout: 10
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("stdout-2999"))
        XCTAssertTrue(result.stderr.contains("stderr-2999"))
    }

    func testRunDoesNotLoseShortStderrAtProcessExit() async throws {
        let runner = ShellCommandRunner()
        for iteration in 0..<100 {
            let marker = "fatal-short-stderr-\(iteration)"
            let result = try await runner.run(
                executable: "/bin/zsh",
                arguments: ["-c", "printf '\(marker)\\n' >&2; exit 1"],
                timeout: 5
            )

            XCTAssertEqual(result.exitCode, 1)
            XCTAssertEqual(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines), marker)
        }
    }

    func testTimeoutTerminatesUncooperativeProcessPromptly() async throws {
        let start = ContinuousClock.now

        do {
            _ = try await ShellCommandRunner().run(
                executable: "/bin/zsh",
                arguments: ["-c", "trap '' TERM; while true; do sleep 1; done"],
                timeout: 0.2
            )
            XCTFail("Expected timeout")
        } catch let error as ShellCommandError {
            XCTAssertTrue(error.isTimeout)
        }

        let elapsed = start.duration(to: .now)
        XCTAssertLessThan(elapsed, .seconds(2))
    }

    func testCallerCancellationTerminatesProcessPromptly() async throws {
        let task = Task {
            try await ShellCommandRunner().run(
                executable: "/bin/zsh",
                arguments: ["-c", "trap '' TERM; while true; do sleep 1; done"],
                timeout: 30
            )
        }
        try await Task.sleep(for: .milliseconds(150))
        let start = ContinuousClock.now
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        XCTAssertLessThan(start.duration(to: .now), .seconds(2))
    }
}
