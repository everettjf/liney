import XCTest
@testable import Liney

final class ReviewServiceTests: XCTestCase {
    func testParserAcceptsJSONAndAttachesReviewer() throws {
        let output = """
        {"findings":[{"title":"Session leak","body":"The child process remains alive.","severity":"high","file":"Liney/Foo.swift","line":42,"category":"reliability"}]}
        """

        let findings = try ReviewOutputParser.parse(output, reviewer: .codex)

        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings[0].title, "Session leak")
        XCTAssertEqual(findings[0].severity, .high)
        XCTAssertEqual(findings[0].file, "Liney/Foo.swift")
        XCTAssertEqual(findings[0].line, 42)
        XCTAssertEqual(findings[0].category, .reliability)
        XCTAssertEqual(findings[0].reviewers, [.codex])
    }

    func testParserExtractsJSONObjectFromSurroundingText() throws {
        let output = """
        Result:
        {"findings":[]}
        """

        XCTAssertEqual(try ReviewOutputParser.parse(output, reviewer: .kimi), [])
    }

    func testMergerCombinesSameLocationAndTitle() {
        let first = ReviewFinding(
            title: "Task can outlive session",
            body: "First explanation",
            severity: .medium,
            file: "Liney/Session.swift",
            line: 18,
            category: .reliability,
            reviewers: [.claudeCode]
        )
        let second = ReviewFinding(
            title: "Task can outlive session",
            body: "Second explanation",
            severity: .high,
            file: "Liney/Session.swift",
            line: 18,
            category: .reliability,
            reviewers: [.codex]
        )

        let merged = ReviewFindingMerger.merge([
            ReviewAgentResult(agent: .claudeCode, findings: [first], rawOutput: "", errorMessage: nil),
            ReviewAgentResult(agent: .codex, findings: [second], rawOutput: "", errorMessage: nil),
        ])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].severity, .high)
        XCTAssertEqual(merged[0].reviewers, [.claudeCode, .codex])
    }

    func testInvocationsUseReadOnlyModesWhenAvailable() {
        let codex = ReviewService.invocation(for: .codex, prompt: "review", repositoryPath: "/repo")
        XCTAssertTrue(codex.arguments.contains("read-only"))
        XCTAssertTrue(codex.arguments.contains("--ephemeral"))

        let claude = ReviewService.invocation(for: .claudeCode, prompt: "review", repositoryPath: "/repo")
        XCTAssertTrue(claude.arguments.contains("plan"))
        XCTAssertTrue(claude.arguments.contains("Read"))

        let kimi = ReviewService.invocation(for: .kimi, prompt: "review", repositoryPath: "/repo")
        XCTAssertTrue(kimi.arguments.contains("--quiet"))
        XCTAssertTrue(kimi.arguments.contains("-p"))
    }

    func testPromptLimitsFindingsToSelectedDiff() {
        let prompt = ReviewService.prompt(
            target: .branchRange(base: "main", target: "feature"),
            focus: [.performance, .security],
            instructions: "Check cancellation."
        )

        XCTAssertTrue(prompt.contains("git diff main...feature"))
        XCTAssertTrue(prompt.contains("read the entire repository"))
        XCTAssertTrue(prompt.contains("report only concrete regressions introduced by the selected diff"))
        XCTAssertTrue(prompt.contains("Check cancellation."))
    }

    func testVerificationParserAcceptsStructuredVerdict() throws {
        let output = """
        {"verdict":"confirmed","rationale":"The task is retained after cancellation."}
        """

        let verification = try ReviewVerificationParser.parse(output)

        XCTAssertEqual(verification.verdict, .confirmed)
        XCTAssertEqual(verification.rationale, "The task is retained after cancellation.")
    }

    func testVerificationPromptIncludesFindingEvidence() {
        let finding = ReviewFinding(
            title: "Task can outlive session",
            body: "Cancellation does not release the task.",
            severity: .high,
            file: "Liney/Session.swift",
            line: 18,
            category: .reliability,
            reviewers: [.codex]
        )

        let prompt = ReviewService.verificationPrompt(finding: finding)

        XCTAssertTrue(prompt.contains("verifying another code reviewer's finding"))
        XCTAssertTrue(prompt.contains("Liney/Session.swift"))
        XCTAssertTrue(prompt.contains("Cancellation does not release the task."))
        XCTAssertTrue(prompt.contains("confirmed|rejected|uncertain"))
    }
}
