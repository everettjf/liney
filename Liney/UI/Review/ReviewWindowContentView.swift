import SwiftUI

struct ReviewWindowContentView: View {
    @ObservedObject var state: ReviewWindowState

    var body: some View {
        Group {
            if state.showsResults {
                resultsView
            } else {
                configurationView
            }
        }
        .background(LineyTheme.appBackground)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if state.showsResults {
                    Button {
                        state.newReview()
                    } label: {
                        Label("New Review", systemImage: "chevron.left")
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if state.isRunning {
                    Button("Cancel") { state.cancel() }
                } else if state.showsResults {
                    Button {
                        state.startReview()
                    } label: {
                        Label("Run Again", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
    }

    private var configurationView: some View {
        VStack(spacing: 0) {
            configurationHeader
            Divider().overlay(LineyTheme.border)

            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        workflowSection(number: "01", title: "选择评审范围", caption: state.repositoryName) {
                            Picker("Diff source", selection: $state.targetMode) {
                                Text("当前修改").tag(0)
                                Text("分支对比").tag(1)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)

                            if state.targetMode == 1 {
                                HStack(spacing: 12) {
                                    branchField("Base branch", value: $state.baseBranch)
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(LineyTheme.mutedText)
                                    branchField("Target branch", value: $state.targetBranch)
                                }
                            }

                            Label(
                                "Agent 可读取整个仓库作为上下文，仅对所选 Diff 输出问题。",
                                systemImage: "lock.open.display"
                            )
                            .font(.system(size: 11))
                            .foregroundStyle(LineyTheme.secondaryText)
                        }

                        workflowSection(
                            number: "02",
                            title: "选择 Reviewer",
                            caption: "\(state.selectedAgents.count) / 3"
                        ) {
                            VStack(spacing: 0) {
                                ForEach(Array(ReviewAgent.allCases.enumerated()), id: \.element) { index, agent in
                                    reviewerRow(agent)
                                    if index < ReviewAgent.allCases.count - 1 {
                                        Divider().overlay(LineyTheme.border)
                                    }
                                }
                            }
                            .background(LineyTheme.panelBackground, in: RoundedRectangle(cornerRadius: 10))
                            .overlay { RoundedRectangle(cornerRadius: 10).stroke(LineyTheme.border) }

                            Text("至少选择 2 个。各 Agent 独立运行，结果按代码位置聚合。")
                                .font(.system(size: 11))
                                .foregroundStyle(LineyTheme.mutedText)
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity, alignment: .top)
                }

                Divider().overlay(LineyTheme.border)

                reviewSidebar
                    .frame(width: 360)
            }
        }
    }

    private var configurationHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.bubble.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(LineyTheme.accent)
                .frame(width: 38, height: 38)
                .background(LineyTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text("New Review")
                    .font(.system(size: 20, weight: .semibold))
                Text("多个 Agent 独立审查同一份代码变更")
                    .font(.system(size: 11))
                    .foregroundStyle(LineyTheme.mutedText)
            }
            Spacer()
            Label("One-pass", systemImage: "bolt.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(LineyTheme.secondaryText)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(LineyTheme.panelBackground, in: Capsule())
                .overlay { Capsule().stroke(LineyTheme.border) }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var reviewSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                workflowSection(
                    number: "03",
                    title: "评审重点",
                    caption: "\(state.selectedFocus.count) selected"
                ) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(ReviewFocus.allCases) { focus in
                            focusButton(focus)
                        }
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text("补充要求")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(LineyTheme.secondaryText)
                        TextEditor(text: $state.additionalInstructions)
                            .font(.system(size: 12))
                            .scrollContentBackground(.hidden)
                            .padding(7)
                            .frame(minHeight: 76)
                            .background(LineyTheme.paneBackground, in: RoundedRectangle(cornerRadius: 7))
                            .overlay { RoundedRectangle(cornerRadius: 7).stroke(LineyTheme.border) }
                    }
                }

                Divider().overlay(LineyTheme.border)

                VStack(alignment: .leading, spacing: 12) {
                    Text("本次 Review")
                        .font(.system(size: 12, weight: .semibold))
                    summaryRow("范围", state.targetMode == 0 ? "当前修改" : "\(state.baseBranch) → \(state.targetBranch)")
                    summaryRow("上下文", "整个仓库")
                    summaryRow("Reviewer", state.selectedAgents.map(\.displayName).sorted().joined(separator: " · "))
                }

                if let message = state.validationMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(LineyTheme.warning)
                }

                Button {
                    state.startReview()
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start Review")
                        Spacer()
                        Text("\(state.selectedAgents.count) agents")
                            .font(.system(size: 10, weight: .medium))
                            .opacity(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(state.repositoryPath == nil)
            }
            .padding(24)
        }
        .background(LineyTheme.sidebarBackground.opacity(0.55))
    }

    private var resultsView: some View {
        VStack(spacing: 0) {
            pageHeader(
                title: "Review Results",
                subtitle: state.isRunning
                    ? "Reviewer 正在并行检查仓库与 Diff。"
                    : "结果按问题归并；不会触发模型之间的后续讨论。"
            )
            .padding(22)

            statusStrip
                .padding(.horizontal, 22)
                .padding(.bottom, 16)

            Divider().overlay(LineyTheme.border)

            if state.isRunning, state.findings.isEmpty {
                Spacer()
                ProgressView("Running \(state.selectedAgents.count) independent reviews…")
                Spacer()
            } else if state.findings.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No Findings",
                    systemImage: "checkmark.seal",
                    description: Text(failedAgentsDescription)
                )
                Spacer()
            } else {
                HSplitView {
                    findingsList
                        .frame(minWidth: 300, idealWidth: 360, maxWidth: 440)
                    findingDetail
                        .frame(minWidth: 460)
                }
            }
        }
    }

    private var statusStrip: some View {
        HStack(spacing: 10) {
            ForEach(ReviewAgent.allCases.filter { state.selectedAgents.contains($0) }) { agent in
                HStack(spacing: 7) {
                    statusIcon(state.statuses[agent] ?? .idle)
                    Text(agent.displayName)
                        .font(.system(size: 12, weight: .medium))
                    Text(statusText(state.statuses[agent] ?? .idle))
                        .font(.system(size: 11))
                        .foregroundStyle(LineyTheme.mutedText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(LineyTheme.panelBackground, in: RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).stroke(LineyTheme.border) }
            }
            Spacer()
            if !state.isRunning {
                Text("\(state.findings.count) merged findings")
                    .font(.system(size: 11))
                    .foregroundStyle(LineyTheme.mutedText)
            }
        }
    }

    private var findingsList: some View {
        List(selection: $state.selectedFindingID) {
            ForEach(state.findings) { finding in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        severityBadge(finding.severity)
                        Spacer()
                        Text("\(finding.reviewers.count)/\(state.selectedAgents.count)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(LineyTheme.mutedText)
                    }
                    Text(finding.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2)
                    if let file = finding.file {
                        Text(file + (finding.line.map { ":\($0)" } ?? ""))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(LineyTheme.mutedText)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 5)
                .tag(finding.id)
            }
        }
        .listStyle(.sidebar)
        .background(LineyTheme.sidebarBackground)
    }

    @ViewBuilder
    private var findingDetail: some View {
        if let finding = state.findings.first(where: { $0.id == state.selectedFindingID }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        severityBadge(finding.severity)
                        if let category = finding.category {
                            Text(category.displayName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(LineyTheme.secondaryText)
                        }
                    }
                    Text(finding.title)
                        .font(.system(size: 22, weight: .semibold))
                    if let file = finding.file {
                        Label(file + (finding.line.map { ":\($0)" } ?? ""), systemImage: "doc.text")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(LineyTheme.accent)
                    }
                    Text(finding.body)
                        .font(.system(size: 13))
                        .textSelection(.enabled)

                    Divider().overlay(LineyTheme.border)
                    Text("Reviewer coverage")
                        .font(.system(size: 13, weight: .semibold))
                    ForEach(ReviewAgent.allCases.filter { state.selectedAgents.contains($0) }) { agent in
                        HStack {
                            Image(systemName: finding.reviewers.contains(agent) ? "checkmark.circle.fill" : "minus.circle")
                                .foregroundStyle(finding.reviewers.contains(agent) ? LineyTheme.success : LineyTheme.mutedText)
                            Text(agent.displayName)
                            Spacer()
                            Text(finding.reviewers.contains(agent) ? "Reported" : "Not reported")
                                .foregroundStyle(LineyTheme.mutedText)
                        }
                        .font(.system(size: 12))
                    }
                }
                .padding(26)
                .frame(maxWidth: 760, alignment: .leading)
            }
            .background(LineyTheme.appBackground)
        } else {
            ContentUnavailableView("Select a finding", systemImage: "text.magnifyingglass")
        }
    }

    private func pageHeader(title: String, subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 24, weight: .semibold))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(LineyTheme.mutedText)
            }
            Spacer()
        }
    }

    private func workflowSection<Content: View>(
        number: String,
        title: String,
        caption: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 9) {
                Text(number)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(LineyTheme.accent)
                    .frame(width: 25, height: 19)
                    .background(LineyTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                Text(title).font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(caption).font(.system(size: 10)).foregroundStyle(LineyTheme.mutedText)
            }
            content()
        }
    }

    private func branchField(_ title: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10)).foregroundStyle(LineyTheme.mutedText)
            TextField(title, text: value)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func reviewerRow(_ agent: ReviewAgent) -> some View {
        Button {
            state.toggleAgent(agent)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: agent.systemImage)
                    .font(.system(size: 18))
                    .foregroundStyle(state.selectedAgents.contains(agent) ? LineyTheme.accent : LineyTheme.secondaryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.displayName).font(.system(size: 12, weight: .medium))
                    Text("\(agent.commandName) · authenticated local CLI")
                        .font(.system(size: 10))
                        .foregroundStyle(LineyTheme.mutedText)
                }
                Spacer()
                Text(agentAvailabilityText(agent))
                    .font(.system(size: 10))
                    .foregroundStyle(state.agentAvailability[agent] == false ? LineyTheme.warning : LineyTheme.success)
                Image(systemName: state.selectedAgents.contains(agent) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(state.selectedAgents.contains(agent) ? LineyTheme.accent : LineyTheme.mutedText)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func focusButton(_ focus: ReviewFocus) -> some View {
        Button {
            state.toggleFocus(focus)
        } label: {
            HStack {
                Image(systemName: state.selectedFocus.contains(focus) ? "checkmark.circle.fill" : "circle")
                Text(focus.displayName).lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .foregroundStyle(state.selectedFocus.contains(focus) ? Color.white : LineyTheme.secondaryText)
        .background(
            state.selectedFocus.contains(focus) ? LineyTheme.accent.opacity(0.72) : LineyTheme.paneBackground,
            in: RoundedRectangle(cornerRadius: 7)
        )
        .overlay { RoundedRectangle(cornerRadius: 7).stroke(LineyTheme.border) }
    }

    private func agentAvailabilityText(_ agent: ReviewAgent) -> String {
        switch state.agentAvailability[agent] ?? nil {
        case true: return "Ready"
        case false: return "Not installed"
        case nil: return "Checking…"
        }
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(LineyTheme.mutedText).frame(width: 78, alignment: .leading)
            Text(value).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 11))
    }

    @ViewBuilder
    private func statusIcon(_ status: ReviewAgentStatus) -> some View {
        switch status {
        case .idle:
            Image(systemName: "circle").foregroundStyle(LineyTheme.mutedText)
        case .running:
            ProgressView().controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(LineyTheme.success)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(LineyTheme.danger)
        }
    }

    private func statusText(_ status: ReviewAgentStatus) -> String {
        switch status {
        case .idle: return "Waiting"
        case .running: return "Reviewing"
        case .completed(let count): return "\(count) findings"
        case .failed: return "Failed"
        }
    }

    private func severityBadge(_ severity: ReviewSeverity) -> some View {
        Text(severity.rawValue.uppercased())
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .foregroundStyle(severity == .critical || severity == .high ? LineyTheme.danger : LineyTheme.warning)
            .background(
                (severity == .critical || severity == .high ? LineyTheme.danger : LineyTheme.warning).opacity(0.12),
                in: Capsule()
            )
    }

    private var failedAgentsDescription: String {
        let failures = state.results.compactMap { result in
            result.errorMessage.map { "\(result.agent.displayName): \($0)" }
        }
        return failures.isEmpty ? "Reviewer 没有发现需要处理的问题。" : failures.joined(separator: "\n")
    }
}
