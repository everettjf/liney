import XCTest
@testable import Liney

final class ReviewServiceTests: XCTestCase {
    func testLineyRepositoryDisplayNameUsesBrandCapitalization() {
        XCTAssertEqual(ReviewRepositoryDisplayName.resolve("liney"), "Liney")
        XCTAssertEqual(ReviewRepositoryDisplayName.resolve("LINEY"), "Liney")
        XCTAssertEqual(ReviewRepositoryDisplayName.resolve("another-repository"), "another-repository")
    }

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

        let gemini = ReviewService.invocation(for: .gemini, prompt: "review", repositoryPath: "/repo")
        XCTAssertTrue(gemini.arguments.contains("plan"))
        XCTAssertTrue(gemini.arguments.contains("json"))

        let opencode = ReviewService.invocation(for: .opencode, prompt: "review", repositoryPath: "/repo")
        XCTAssertTrue(opencode.arguments.contains("run"))
        XCTAssertTrue(opencode.arguments.contains("/repo"))
        XCTAssertTrue(opencode.arguments.contains("json"))

        let qwen = ReviewService.invocation(for: .qwenCode, prompt: "review", repositoryPath: "/repo")
        XCTAssertTrue(qwen.arguments.contains("plan"))
        XCTAssertTrue(qwen.arguments.contains("10m"))

        let cursor = ReviewService.invocation(for: .cursorAgent, prompt: "review", repositoryPath: "/repo")
        XCTAssertTrue(cursor.arguments.contains("-p"))
        XCTAssertTrue(cursor.arguments.contains("json"))

        let copilot = ReviewService.invocation(for: .githubCopilot, prompt: "review", repositoryPath: "/repo")
        XCTAssertTrue(copilot.arguments.contains("--no-ask-user"))
        XCTAssertTrue(copilot.arguments.contains("--deny-tool=write"))
        XCTAssertTrue(copilot.arguments.contains("--disable-builtin-mcps"))
    }

    func testFinalOutputUnwrapsSupportedCLIEnvelopes() {
        XCTAssertEqual(
            ReviewService.finalOutput(from: #"{"response":"gemini-result"}"#, agent: .gemini),
            "gemini-result"
        )
        XCTAssertEqual(
            ReviewService.finalOutput(from: #"{"result":"cursor-result"}"#, agent: .cursorAgent),
            "cursor-result"
        )
        XCTAssertEqual(
            ReviewService.finalOutput(
                from: #"[{"type":"system"},{"type":"result","result":"qwen-result"}]"#,
                agent: .qwenCode
            ),
            "qwen-result"
        )
        XCTAssertEqual(
            ReviewService.finalOutput(
                from: #"{"part":{"type":"text","text":"opencode-result"}}"#,
                agent: .opencode
            ),
            "opencode-result"
        )
    }

    func testOpenCodeEnvironmentDeniesWritesAndLimitsShell() {
        let environment = ReviewService.environment(for: .opencode, base: ["PATH": "/bin"])
        let permissions = environment?["OPENCODE_PERMISSION"] ?? ""

        XCTAssertEqual(environment?["PATH"], "/bin")
        XCTAssertTrue(permissions.contains(#""edit":"deny""#))
        XCTAssertTrue(permissions.contains(#""*":"deny""#))
        XCTAssertTrue(permissions.contains("git diff*"))
    }

    func testDefaultAgentsRemainThreeAfterAddingProviders() {
        XCTAssertEqual(ReviewAgent.defaults, [.claudeCode, .codex, .kimi])
        XCTAssertEqual(ReviewAgent.allCases.count, 8)
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
