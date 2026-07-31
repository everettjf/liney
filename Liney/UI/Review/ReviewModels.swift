import Foundation

nonisolated enum ReviewAgent: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case claudeCode
    case codex
    case kimi
    case gemini
    case opencode
    case qwenCode
    case cursorAgent
    case githubCopilot

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .kimi: return "Kimi"
        case .gemini: return "Gemini CLI"
        case .opencode: return "OpenCode"
        case .qwenCode: return "Qwen Code"
        case .cursorAgent: return "Cursor Agent"
        case .githubCopilot: return "GitHub Copilot"
        }
    }

    var commandName: String {
        switch self {
        case .claudeCode: return "claude"
        case .codex: return "codex"
        case .kimi: return "kimi"
        case .gemini: return "gemini"
        case .opencode: return "opencode"
        case .qwenCode: return "qwen"
        case .cursorAgent: return "cursor-agent"
        case .githubCopilot: return "copilot"
        }
    }

    var systemImage: String {
        switch self {
        case .claudeCode: return "c.circle.fill"
        case .codex: return "o.circle.fill"
        case .kimi: return "k.circle.fill"
        case .gemini: return "g.circle.fill"
        case .opencode: return "terminal.fill"
        case .qwenCode: return "q.circle.fill"
        case .cursorAgent: return "cursorarrow.rays"
        case .githubCopilot: return "chevron.left.forwardslash.chevron.right"
        }
    }

    static let defaults: Set<ReviewAgent> = [.claudeCode, .codex, .kimi]
}

nonisolated enum ReviewFocus: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case stability
    case reliability
    case businessLogic
    case performance
    case security
    case concurrency
    case compatibility
    case testing

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stability: return "Stability"
        case .reliability: return "Reliability"
        case .businessLogic: return "Business Logic"
        case .performance: return "Performance"
        case .security: return "Security & Privacy"
        case .concurrency: return "Concurrency"
        case .compatibility: return "API Compatibility"
        case .testing: return "Test Coverage"
        }
    }

    static let defaults: Set<ReviewFocus> = [.stability, .reliability, .businessLogic, .performance]
}

nonisolated enum ReviewTarget: Hashable, Sendable {
    case currentChanges
    case branchRange(base: String, target: String)

    var displayName: String {
        switch self {
        case .currentChanges:
            return "Current changes"
        case .branchRange(let base, let target):
            return "\(base) → \(target)"
        }
    }
}

nonisolated enum ReviewSeverity: String, Codable, CaseIterable, Hashable, Sendable {
    case critical
    case high
    case medium
    case low

    var rank: Int {
        switch self {
        case .critical: return 0
        case .high: return 1
        case .medium: return 2
        case .low: return 3
        }
    }
}

nonisolated struct ReviewFinding: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var title: String
    var body: String
    var severity: ReviewSeverity
    var file: String?
    var line: Int?
    var category: ReviewFocus?
    var reviewers: Set<ReviewAgent>

    enum CodingKeys: String, CodingKey {
        case title, body, severity, file, line, category
    }

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        severity: ReviewSeverity,
        file: String?,
        line: Int?,
        category: ReviewFocus?,
        reviewers: Set<ReviewAgent>
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.severity = severity
        self.file = file
        self.line = line
        self.category = category
        self.reviewers = reviewers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        severity = try container.decode(ReviewSeverity.self, forKey: .severity)
        file = try container.decodeIfPresent(String.self, forKey: .file)
        line = try container.decodeIfPresent(Int.self, forKey: .line)
        category = try container.decodeIfPresent(ReviewFocus.self, forKey: .category)
        reviewers = []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(body, forKey: .body)
        try container.encode(severity, forKey: .severity)
        try container.encodeIfPresent(file, forKey: .file)
        try container.encodeIfPresent(line, forKey: .line)
        try container.encodeIfPresent(category, forKey: .category)
    }
}

nonisolated struct ReviewAgentResult: Sendable {
    let agent: ReviewAgent
    let findings: [ReviewFinding]
    let rawOutput: String
    let errorMessage: String?
}

nonisolated enum ReviewAgentStatus: Equatable {
    case idle
    case running
    case completed(Int)
    case failed(String)
}

nonisolated struct ReviewVerificationKey: Hashable {
    let findingID: UUID
    let agent: ReviewAgent
}

nonisolated enum ReviewVerdict: String, Codable, Sendable {
    case confirmed
    case rejected
    case uncertain

    var displayName: String {
        switch self {
        case .confirmed: return "Confirmed"
        case .rejected: return "Rejected"
        case .uncertain: return "Uncertain"
        }
    }
}

nonisolated struct ReviewVerification: Codable, Equatable, Sendable {
    let verdict: ReviewVerdict
    let rationale: String
}

nonisolated enum ReviewVerificationStatus: Equatable {
    case running
    case completed(ReviewVerification)
    case failed(String)
}
