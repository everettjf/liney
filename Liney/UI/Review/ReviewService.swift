import Foundation

nonisolated protocol ReviewCommandRunning: Sendable {
    func run(
        executable: String,
        arguments: [String],
        currentDirectory: String?,
        environment: [String: String]?,
        timeout: TimeInterval
    ) async throws -> ShellCommandResult
}

extension ShellCommandRunner: ReviewCommandRunning {}

nonisolated struct ReviewService: Sendable {
    private let runner: any ReviewCommandRunning
    private let timeout: TimeInterval

    init(runner: any ReviewCommandRunning = ShellCommandRunner(), timeout: TimeInterval = 600) {
        self.runner = runner
        self.timeout = timeout
    }

    func run(
        agents: Set<ReviewAgent>,
        target: ReviewTarget,
        focus: Set<ReviewFocus>,
        instructions: String,
        repositoryPath: String,
        environment: [String: String]? = nil,
        onStarted: @escaping @Sendable (ReviewAgent) async -> Void,
        onFinished: @escaping @Sendable (ReviewAgentResult) async -> Void
    ) async -> [ReviewAgentResult] {
        await withTaskGroup(of: ReviewAgentResult.self, returning: [ReviewAgentResult].self) { group in
            for agent in agents {
                group.addTask {
                    await onStarted(agent)
                    let result = await runAgent(
                        agent,
                        target: target,
                        focus: focus,
                        instructions: instructions,
                        repositoryPath: repositoryPath,
                        environment: environment
                    )
                    await onFinished(result)
                    return result
                }
            }

            var results: [ReviewAgentResult] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.agent.displayName < $1.agent.displayName }
        }
    }

    func runAgent(
        _ agent: ReviewAgent,
        target: ReviewTarget,
        focus: Set<ReviewFocus>,
        instructions: String,
        repositoryPath: String,
        environment: [String: String]? = nil
    ) async -> ReviewAgentResult {
        let prompt = Self.prompt(target: target, focus: focus, instructions: instructions)
        let invocation = Self.invocation(for: agent, prompt: prompt, repositoryPath: repositoryPath)

        do {
            let result = try await runner.run(
                executable: invocation.executable,
                arguments: invocation.arguments,
                currentDirectory: repositoryPath,
                environment: environment,
                timeout: timeout
            )
            guard result.exitCode == 0 else {
                let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return ReviewAgentResult(
                    agent: agent,
                    findings: [],
                    rawOutput: result.stdout,
                    errorMessage: message.isEmpty ? "\(agent.displayName) exited with code \(result.exitCode)." : message
                )
            }
            let output = Self.finalOutput(from: result.stdout, agent: agent)
            let findings = try ReviewOutputParser.parse(output, reviewer: agent)
            return ReviewAgentResult(agent: agent, findings: findings, rawOutput: output, errorMessage: nil)
        } catch {
            return ReviewAgentResult(
                agent: agent,
                findings: [],
                rawOutput: "",
                errorMessage: error.localizedDescription
            )
        }
    }

    static func prompt(target: ReviewTarget, focus: Set<ReviewFocus>, instructions: String) -> String {
        let targetText: String
        switch target {
        case .currentChanges:
            targetText = """
            Review all current changes relative to HEAD, including staged, unstaged, and untracked files.
            Use git status, git diff, and git diff --cached as needed.
            """
        case .branchRange(let base, let target):
            targetText = """
            Review the changes in the merge-base diff \(base)...\(target).
            Resolve both refs before reviewing and use git diff \(base)...\(target).
            """
        }

        let focusText = focus
            .sorted { $0.rawValue < $1.rawValue }
            .map { "\($0.rawValue): \($0.displayName)" }
            .joined(separator: ", ")
        let extra = instructions.trimmingCharacters(in: .whitespacesAndNewlines)

        return """
        You are one independent code reviewer. This is a strictly read-only task.
        Do not modify files, run formatters, install dependencies, create commits, or change repository state.
        You may read the entire repository for context, but report only concrete regressions introduced by the selected diff.

        Target:
        \(targetText)

        Review focus:
        \(focusText)

        \(extra.isEmpty ? "" : "Additional instructions:\n\(extra)\n")
        Return ONLY valid JSON with this exact top-level shape:
        {"findings":[{"title":"short actionable title","body":"why this is a problem and when it occurs","severity":"critical|high|medium|low","file":"repository-relative/path.swift","line":123,"category":"stability|reliability|businessLogic|performance|security|concurrency|compatibility|testing"}]}

        Use an empty findings array when there are no actionable issues. Do not include markdown fences.
        Each finding must identify a changed file and, when possible, a changed line.
        """
    }

    static func invocation(
        for agent: ReviewAgent,
        prompt: String,
        repositoryPath: String
    ) -> (executable: String, arguments: [String]) {
        switch agent {
        case .claudeCode:
            return (
                "/usr/bin/env",
                [
                    "claude", "-p", "--output-format", "json",
                    "--permission-mode", "plan",
                    "--allowedTools", "Read", "Grep", "Glob",
                    "Bash(git status:*)", "Bash(git diff:*)", "Bash(git log:*)",
                    prompt,
                ]
            )
        case .codex:
            return (
                "/usr/bin/env",
                [
                    "codex", "exec", "--cd", repositoryPath, "--sandbox", "read-only",
                    "--ephemeral", "--color", "never", prompt,
                ]
            )
        case .kimi:
            return (
                "/usr/bin/env",
                ["kimi", "--quiet", "-p", prompt]
            )
        }
    }

    static func finalOutput(from stdout: String, agent: ReviewAgent) -> String {
        guard agent == .claudeCode,
              let data = stdout.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? String else {
            return stdout
        }
        return result
    }
}

nonisolated enum ReviewOutputParser {
    private struct Envelope: Decodable {
        let findings: [ReviewFinding]
    }

    static func parse(_ output: String, reviewer: ReviewAgent) throws -> [ReviewFinding] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let json = extractJSONObject(from: trimmed)
        guard let data = json.data(using: .utf8) else {
            throw ReviewParsingError.invalidOutput
        }
        var findings = try JSONDecoder().decode(Envelope.self, from: data).findings
        for index in findings.indices {
            findings[index].reviewers = [reviewer]
        }
        return findings
    }

    private static func extractJSONObject(from text: String) -> String {
        if text.hasPrefix("{"), text.hasSuffix("}") {
            return text
        }
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start <= end else {
            return text
        }
        return String(text[start...end])
    }
}

nonisolated enum ReviewParsingError: LocalizedError {
    case invalidOutput

    var errorDescription: String? {
        "The reviewer did not return valid structured JSON."
    }
}

nonisolated enum ReviewFindingMerger {
    static func merge(_ results: [ReviewAgentResult]) -> [ReviewFinding] {
        var merged: [String: ReviewFinding] = [:]

        for result in results {
            for finding in result.findings {
                let key = duplicateKey(for: finding)
                if var existing = merged[key] {
                    existing.reviewers.formUnion(finding.reviewers)
                    if finding.severity.rank < existing.severity.rank {
                        existing.severity = finding.severity
                    }
                    merged[key] = existing
                } else {
                    merged[key] = finding
                }
            }
        }

        return merged.values.sorted {
            if $0.severity.rank != $1.severity.rank {
                return $0.severity.rank < $1.severity.rank
            }
            if $0.reviewers.count != $1.reviewers.count {
                return $0.reviewers.count > $1.reviewers.count
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private static func duplicateKey(for finding: ReviewFinding) -> String {
        let normalizedTitle = finding.title
            .lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return [
            finding.file?.lowercased() ?? "",
            finding.line.map(String.init) ?? "",
            normalizedTitle,
        ].joined(separator: "|")
    }
}
