//
//  WorkspaceStoreTests.swift
//  LineyTests
//
//  Author: everettjf
//

import XCTest
@testable import Liney

@MainActor
final class WorkspaceStoreTests: XCTestCase {
    override func tearDown() {
        LocalizationManager.shared.updateSelectedLanguage(.automatic)
        super.tearDown()
    }

    func testOpenWorkspaceAsRepositoryAddsRepositoryWorkspaceWithoutChangingLocalWorkspace() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        try runProcess(
            executable: "/usr/bin/env",
            arguments: ["git", "init", "-b", "main"],
            currentDirectory: directoryURL.path
        )

        let store = WorkspaceStore(persistsWorkspaceState: false)
        let localWorkspace = WorkspaceModel(localDirectoryPath: directoryURL.path, name: "demo")
        store.workspaces = [localWorkspace]
        store.selectedWorkspaceID = localWorkspace.id

        try await store.openWorkspaceAsRepository(localWorkspace, persistAfterChange: false)

        XCTAssertEqual(store.workspaces.count, 2)
        XCTAssertEqual(store.workspaces.filter { !$0.supportsRepositoryFeatures }.count, 1)
        XCTAssertEqual(store.workspaces.filter(\.supportsRepositoryFeatures).count, 1)
        XCTAssertTrue(store.workspaces.contains(where: { $0.id == localWorkspace.id && !$0.supportsRepositoryFeatures }))
        XCTAssertEqual(
            store.workspaces.first(where: \.supportsRepositoryFeatures).map {
                URL(fileURLWithPath: $0.repositoryRoot).standardizedFileURL.path
            },
            directoryURL.standardizedFileURL.path
        )
    }

    func testLoadIfNeededAppliesInitialAppLanguageToLocalizationManager() async {
        LocalizationManager.shared.updateSelectedLanguage(.automatic)
        let store = WorkspaceStore(
            initialAppSettings: AppSettings(appLanguage: .simplifiedChinese),
            persistsWorkspaceState: false
        )

        await store.loadIfNeeded()

        XCTAssertEqual(LocalizationManager.shared.selectedLanguage, .simplifiedChinese)
    }

    func testUpdateAppSettingsPublishesSelectedLanguageToLocalizationManager() {
        LocalizationManager.shared.updateSelectedLanguage(.automatic)
        let store = WorkspaceStore(persistsWorkspaceState: false)

        store.updateAppSettings(AppSettings(appLanguage: .simplifiedChinese))

        XCTAssertEqual(store.appSettings.appLanguage, .simplifiedChinese)
        XCTAssertEqual(LocalizationManager.shared.selectedLanguage, .simplifiedChinese)
    }

    func testUpdateAppSettingsPreservesInterfaceScale() {
        let store = WorkspaceStore(persistsWorkspaceState: false)

        store.updateAppSettings(AppSettings(uiScale: 1.25))

        XCTAssertEqual(store.appSettings.uiScale, 1.25)
    }

    func testCommandPaletteItemsLocalizeForSimplifiedChinese() {
        LocalizationManager.shared.updateSelectedLanguage(.simplifiedChinese)
        let store = WorkspaceStore(persistsWorkspaceState: false)

        let items = store.commandPaletteItems

        XCTAssertTrue(items.contains(where: { $0.id == "overview" && $0.title == "打开工作区概览" }))
        XCTAssertTrue(items.contains(where: { $0.id == "settings" && $0.title == "打开设置" }))
        XCTAssertTrue(items.contains(where: { $0.id == "check-updates" && $0.title == "检查 Liney 更新" }))
    }

    func testSleepPreventionStringsLocalizeForSimplifiedChinese() {
        LocalizationManager.shared.updateSelectedLanguage(.simplifiedChinese)
        let store = WorkspaceStore(persistsWorkspaceState: false)

        XCTAssertEqual(store.sleepPreventionStatusText, "禁止休眠")
        XCTAssertEqual(store.sleepPreventionPrimaryActionLabel, "开始禁止休眠")
        XCTAssertEqual(store.sleepPreventionPrimaryActionHelpText, "为 macOS 启用禁止休眠：1 小时")
    }

    func testModelDisplayStringsLocalizeForSimplifiedChinese() {
        LocalizationManager.shared.updateSelectedLanguage(.simplifiedChinese)

        XCTAssertEqual(WorkspaceKind.repository.displayName, "仓库")
        XCTAssertEqual(WorkspaceKind.localTerminal.displayName, "本地终端")
        XCTAssertEqual(SessionBackendKind.localShell.displayName, "本地 Shell")
        XCTAssertEqual(WorkspaceActivityKind.workflow.displayName, "工作流")
        XCTAssertEqual(GlobalCanvasColorGroup.slate.title, "石板灰")
        XCTAssertEqual(WorkspaceTabStateRecord.makeDefault(for: "/tmp/liney").title, "标签页 1")
    }

    func testWorktreeAndRemoteStringsLocalizeForSimplifiedChinese() throws {
        LocalizationManager.shared.updateSelectedLanguage(.simplifiedChinese)

        let worktree = WorktreeModel(
            path: "/tmp/liney-main",
            branch: "main",
            head: "abc123",
            isMainWorktree: true,
            isLocked: false,
            lockReason: nil
        )
        XCTAssertEqual(worktree.displayName, "main")
        XCTAssertEqual(worktree.branchLabel, "main")
        XCTAssertEqual(
            L10nTable.string(for: "remote.activity.openedShell", language: .simplifiedChinese),
            "已打开远程目标 Shell"
        )
        XCTAssertEqual(RemoteSessionCoordinatorError.missingTarget.errorDescription, "找不到所选远程目标。")
    }

    func testRememberedAgentPresetSelectionAddsBuiltInPresetAndMarksItPreferred() {
        let customPreset = AgentPreset(
            name: "Custom Review",
            launchPath: "/usr/bin/env",
            arguments: ["custom-agent", "review"]
        )

        let selection = lineyRememberedAgentPresetSelection(
            currentPresets: [customPreset],
            selectedPresetID: AgentPreset.claudeCode.id
        )

        XCTAssertEqual(selection.preferredPresetID, customPreset.id)
        XCTAssertTrue(selection.presets.contains(where: { $0.id == customPreset.id }))
    }

    func testRememberedSSHPresetSelectionKeepsSelectedPresetPreferred() {
        let selection = lineyRememberedSSHPresetSelection(
            currentPresets: SSHPreset.builtInPresets,
            selectedPresetID: SSHPreset.yazi.id
        )

        XCTAssertEqual(selection.preferredPresetID, SSHPreset.yazi.id)
        XCTAssertEqual(selection.presets.map(\.id), SSHPreset.builtInPresets.map(\.id))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
        let directoryURL = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private func runProcess(
        executable: String,
        arguments: [String],
        currentDirectory: String
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stdout = String(decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let stderr = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            XCTFail("Command failed: \(arguments.joined(separator: " "))\nstdout: \(stdout)\nstderr: \(stderr)")
            return
        }
    }
}
