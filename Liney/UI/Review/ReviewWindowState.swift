import Combine
import Foundation

@MainActor
final class ReviewWindowState: ObservableObject {
    @Published var repositoryPath: String?
    @Published var repositoryName = ""
    @Published var targetMode = 0
    @Published var baseBranch = "main"
    @Published var targetBranch = "HEAD"
    @Published var availableBranches: [String] = []
    @Published var selectedAgents: Set<ReviewAgent> = ReviewAgent.defaults
    @Published var agentAvailability: [ReviewAgent: Bool?] = [:]
    @Published var selectedFocus: Set<ReviewFocus> = ReviewFocus.defaults
    @Published var additionalInstructions = ""
    @Published var statuses: [ReviewAgent: ReviewAgentStatus] = [:]
    @Published var results: [ReviewAgentResult] = []
    @Published var findings: [ReviewFinding] = []
    @Published var verifications: [ReviewVerificationKey: ReviewVerificationStatus] = [:]
    @Published var selectedFindingID: UUID?
    @Published var isRunning = false
    @Published var validationMessage: String?
    @Published var showsResults = false

    private let service: ReviewService
    private let commandRunner = ShellCommandRunner()
    private var reviewTask: Task<Void, Never>?
    private var branchTask: Task<Void, Never>?
    private var verificationTasks: [ReviewVerificationKey: Task<Void, Never>] = [:]
    private var runtimeEnvironment: [String: String]?

    init(service: ReviewService = ReviewService()) {
        self.service = service
        ReviewAgent.allCases.forEach { statuses[$0] = .idle }
    }

    deinit {
        reviewTask?.cancel()
        branchTask?.cancel()
        verificationTasks.values.forEach { $0.cancel() }
    }

    func load(repositoryPath: String?, repositoryName: String) {
        reviewTask?.cancel()
        branchTask?.cancel()
        verificationTasks.values.forEach { $0.cancel() }
        verificationTasks = [:]
        self.repositoryPath = repositoryPath
        self.repositoryName = repositoryName
        targetMode = 0
        selectedAgents = ReviewAgent.defaults
        agentAvailability = Dictionary(uniqueKeysWithValues: ReviewAgent.allCases.map { ($0, nil) })
        selectedFocus = ReviewFocus.defaults
        additionalInstructions = ""
        statuses = Dictionary(uniqueKeysWithValues: ReviewAgent.allCases.map { ($0, .idle) })
        results = []
        findings = []
        verifications = [:]
        selectedFindingID = nil
        isRunning = false
        validationMessage = nil
        showsResults = false
        loadRepositoryContext()
    }

    func toggleAgent(_ agent: ReviewAgent) {
        guard !isRunning else { return }
        if selectedAgents.contains(agent) {
            guard selectedAgents.count > 1 else {
                validationMessage = "Select at least one reviewer."
                return
            }
            selectedAgents.remove(agent)
        } else {
            guard selectedAgents.count < 3 else {
                validationMessage = "Select no more than three reviewers."
                return
            }
            guard agentAvailability[agent] != false else {
                validationMessage = "\(agent.displayName) CLI is unavailable. Install it and sign in first."
                return
            }
            selectedAgents.insert(agent)
        }
        validationMessage = nil
    }

    func toggleFocus(_ focus: ReviewFocus) {
        if selectedFocus.contains(focus) {
            selectedFocus.remove(focus)
        } else {
            selectedFocus.insert(focus)
        }
    }

    func startReview() {
        guard let repositoryPath else {
            validationMessage = "Select a local Git repository."
            return
        }
        guard selectedAgents.count >= 1, selectedAgents.count <= 3 else {
            validationMessage = "Select one to three reviewers."
            return
        }
        let unavailable = selectedAgents.filter { agentAvailability[$0] == false }
        guard unavailable.isEmpty else {
            validationMessage = "\(unavailable.map(\.displayName).sorted().joined(separator: ", ")) CLI is unavailable."
            return
        }
        guard !selectedFocus.isEmpty else {
            validationMessage = "Select at least one review category."
            return
        }
        let target: ReviewTarget
        if targetMode == 0 {
            target = .currentChanges
        } else {
            let base = baseBranch.trimmingCharacters(in: .whitespacesAndNewlines)
            let head = targetBranch.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !base.isEmpty, !head.isEmpty else {
                validationMessage = "Enter both a base branch and a target branch."
                return
            }
            target = .branchRange(base: base, target: head)
        }

        validationMessage = nil
        isRunning = true
        showsResults = true
        results = []
        findings = []
        verifications = [:]
        selectedFindingID = nil
        statuses = Dictionary(uniqueKeysWithValues: ReviewAgent.allCases.map { ($0, .idle) })

        let agents = selectedAgents
        let focus = selectedFocus
        let instructions = additionalInstructions
        reviewTask = Task {
            let completed = await service.run(
                agents: agents,
                target: target,
                focus: focus,
                instructions: instructions,
                repositoryPath: repositoryPath,
                environment: runtimeEnvironment,
                onStarted: { agent in
                    await MainActor.run { [weak self] in self?.statuses[agent] = .running }
                },
                onFinished: { result in
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        if let error = result.errorMessage {
                            statuses[result.agent] = .failed(error)
                        } else {
                            statuses[result.agent] = .completed(result.findings.count)
                        }
                    }
                }
            )
            guard !Task.isCancelled else { return }
            results = completed
            findings = ReviewFindingMerger.merge(completed)
            selectedFindingID = findings.first?.id
            isRunning = false
        }
    }

    func cancel() {
        reviewTask?.cancel()
        reviewTask = nil
        isRunning = false
        for agent in selectedAgents where statuses[agent] == .running {
            statuses[agent] = .failed("Cancelled")
        }
    }

    func verify(_ finding: ReviewFinding, with agent: ReviewAgent) {
        guard let repositoryPath,
              !finding.reviewers.contains(agent),
              agentAvailability[agent] != false else { return }
        let key = ReviewVerificationKey(findingID: finding.id, agent: agent)
        guard verifications[key] == nil else { return }

        verifications[key] = .running
        verificationTasks[key] = Task {
            let result = await service.verifyFinding(
                finding,
                with: agent,
                repositoryPath: repositoryPath,
                environment: runtimeEnvironment
            )
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let verification):
                verifications[key] = .completed(verification)
            case .failure(let error):
                verifications[key] = .failed(error.localizedDescription)
            }
            verificationTasks[key] = nil
        }
    }

    func newReview() {
        showsResults = false
        validationMessage = nil
    }

    func verificationStatus(for findingID: UUID, agent: ReviewAgent) -> ReviewVerificationStatus? {
        verifications[ReviewVerificationKey(findingID: findingID, agent: agent)]
    }

    private func loadRepositoryContext() {
        guard let repositoryPath else {
            availableBranches = []
            return
        }
        branchTask = Task {
            runtimeEnvironment = await resolvedLoginEnvironment()
            await loadAgentAvailability(repositoryPath: repositoryPath)
            let result = try? await commandRunner.run(
                executable: "/usr/bin/env",
                arguments: ["git", "for-each-ref", "--format=%(refname:short)", "refs/heads", "refs/remotes"],
                currentDirectory: repositoryPath,
                environment: runtimeEnvironment
            )
            guard !Task.isCancelled else { return }
            let branches = result?.stdout
                .split(separator: "\n")
                .map(String.init)
                .filter { !$0.contains("->") } ?? []
            availableBranches = Array(Set(branches)).sorted()
            if branches.contains("main") {
                baseBranch = "main"
            } else if branches.contains("master") {
                baseBranch = "master"
            } else if let first = branches.first {
                baseBranch = first
            }
        }
    }

    private func resolvedLoginEnvironment() async -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        guard let shell = CurrentUserLoginShell.path(),
              let result = try? await commandRunner.run(
                executable: shell,
                arguments: ["-lc", "printf %s \"$PATH\""]
              ),
              result.exitCode == 0 else {
            return environment
        }
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.isEmpty {
            environment["PATH"] = path
        }
        return environment
    }

    private func loadAgentAvailability(repositoryPath: String) async {
        await withTaskGroup(of: (ReviewAgent, Bool).self) { group in
            for agent in ReviewAgent.allCases {
                group.addTask { [commandRunner, runtimeEnvironment] in
                    let result = try? await commandRunner.run(
                        executable: "/usr/bin/env",
                        arguments: ["which", agent.commandName],
                        currentDirectory: repositoryPath,
                        environment: runtimeEnvironment
                    )
                    return (agent, result?.exitCode == 0)
                }
            }
            for await (agent, available) in group {
                agentAvailability[agent] = available
            }
        }
    }
}
