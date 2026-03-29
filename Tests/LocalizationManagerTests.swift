//
//  LocalizationManagerTests.swift
//  LineyTests
//
//  Author: everettjf
//

import XCTest
@testable import Liney

final class LocalizationManagerTests: XCTestCase {
    override func tearDown() {
        LocalizationManager.shared.updateSelectedLanguage(.automatic)
        super.tearDown()
    }

    func testAutomaticMapsSimplifiedChineseIdentifiersToChinese() {
        let language = LocalizationManager.resolveAutomaticLanguage(
            preferredLanguages: ["zh-Hans-CN"]
        )

        XCTAssertEqual(language, .simplifiedChinese)
    }

    func testAutomaticPrefersFirstSupportedLanguage() {
        let language = LocalizationManager.resolveAutomaticLanguage(
            preferredLanguages: ["en-US", "zh-Hans-US"]
        )

        XCTAssertEqual(language, .english)
    }

    func testAutomaticFallsBackToEnglishForUnsupportedLanguages() {
        let language = LocalizationManager.resolveAutomaticLanguage(
            preferredLanguages: ["ja-JP"]
        )

        XCTAssertEqual(language, .english)
    }

    func testMissingChineseTranslationFallsBackToEnglish() {
        XCTAssertEqual(
            L10nTable.string(for: "test.fallback.onlyEnglish", language: .simplifiedChinese),
            "Only English"
        )
    }

    func testSettingsCoreStringsResolveInEnglish() {
        XCTAssertEqual(L10nTable.string(for: "settings.section.general.title", language: .english), "General")
        XCTAssertEqual(L10nTable.string(for: "settings.sidebarGroup.app", language: .english), "App")
        XCTAssertEqual(L10nTable.string(for: "settings.section.terminal.title", language: .english), "Terminal")
        XCTAssertEqual(L10nTable.string(for: "settings.button.cancel", language: .english), "Cancel")
        XCTAssertEqual(L10nTable.string(for: "settings.general.language.title", language: .english), "Language")
        XCTAssertEqual(L10nTable.string(for: "settings.general.language.appliesImmediately", language: .english), "Changes apply immediately throughout Liney.")
        XCTAssertEqual(L10nTable.string(for: "main.hapi.launchCurrentProject", language: .english), "Launch HAPI in Current Project")
        XCTAssertEqual(L10nTable.string(for: "settings.general.terminal.group", language: .english), "Terminal")
        XCTAssertEqual(L10nTable.string(for: "settings.general.terminal.useCustomFont", language: .english), "Use custom terminal font")
        XCTAssertEqual(L10nTable.string(for: "settings.general.terminal.useCustomFontSize", language: .english), "Use custom terminal font size")
        XCTAssertEqual(L10nTable.string(for: "settings.general.terminal.previewTitle", language: .english), "Preview")
        XCTAssertEqual(L10nTable.string(for: "settings.sidebar.visibility.group", language: .english), "Sidebar")
        XCTAssertEqual(L10nTable.string(for: "settings.sidebar.defaultIcons.repository.title", language: .english), "Repository")
        XCTAssertEqual(L10nTable.string(for: "settings.updates.group", language: .english), "Automatic Updates")
        XCTAssertEqual(L10nTable.string(for: "settings.updates.checkNow", language: .english), "Check for Updates Now")
        XCTAssertEqual(L10nTable.string(for: "settings.shortcuts.intro", language: .english), "Liney shortcuts are routed through the app menu so they continue to work while a terminal pane has focus.")
        XCTAssertEqual(L10nTable.string(for: "settings.shortcuts.resetAll", language: .english), "Reset All to Defaults")
        XCTAssertEqual(L10nTable.string(for: "settings.workspace.group", language: .english), "Workspace")
        XCTAssertEqual(L10nTable.string(for: "settings.workspace.runScript", language: .english), "Run script")
        XCTAssertEqual(L10nTable.string(for: "settings.workspace.workflowsHint", language: .english), "Create reusable playbooks that chain setup, run, and agent launch.")
        XCTAssertEqual(L10nTable.string(for: "settings.workspace.emptyState", language: .english), "Select a workspace to edit repository-specific settings.")
        XCTAssertEqual(L10nTable.string(for: "settings.workspace.agentPreset.name", language: .english), "Name")
        XCTAssertEqual(L10nTable.string(for: "settings.workspace.remoteTarget.host", language: .english), "Host")
        XCTAssertEqual(L10nTable.string(for: "settings.workspace.workflow.localShell", language: .english), "Local shell")
        XCTAssertEqual(L10nTable.string(for: "settings.workspace.workflow.noAgent", language: .english), "No agent")
        XCTAssertEqual(L10nTable.string(for: "settings.sidebarAppearance.title", language: .english), "Sidebar appearance")
        XCTAssertEqual(L10nTable.string(for: "settings.sidebarIconEditor.random", language: .english), "Random")
        XCTAssertEqual(L10nTable.string(for: "settings.sidebarIconCustomization.title", language: .english), "Customize Sidebar Icon")
        XCTAssertEqual(L10nTable.string(for: "settings.shortcuts.category.general", language: .english), "General")
        XCTAssertEqual(L10nTable.string(for: "settings.workflow.localSession.reuseFocused", language: .english), "Reuse focused")
        XCTAssertEqual(L10nTable.string(for: "settings.workflow.agent.none", language: .english), "No agent")
        XCTAssertEqual(L10nTable.string(for: "settings.sidebarIcon.style.solid", language: .english), "Solid")
        XCTAssertEqual(L10nTable.string(for: "settings.sidebarIcon.palette.blue", language: .english), "Blue")
        XCTAssertEqual(L10nTable.string(for: "settings.shortcuts.action.toggleCommandPalette.title", language: .english), "Command Palette")
        XCTAssertEqual(L10nTable.string(for: "settings.shortcuts.action.toggleCommandPalette.subtitle", language: .english), "Search and run workspace actions.")
        XCTAssertEqual(
            L10nTable.string(for: "settings.general.behavior.refreshIntervalHint", language: .english),
            "Controls how often Liney automatically refreshes repository and worktree status when automatic refresh is enabled. Minimum 10 seconds."
        )
        XCTAssertEqual(L10nTable.string(for: "settings.shortcuts.action.hideApp.title", language: .english), "Hide App")
        XCTAssertEqual(L10nTable.string(for: "settings.shortcuts.action.minimizeWindow.title", language: .english), "Minimize Window")
    }

    func testSettingsCoreStringsResolveInSimplifiedChinese() {
        XCTAssertEqual(L10nTable.string(for: "settings.section.general.title", language: .simplifiedChinese), "通用")
        XCTAssertEqual(L10nTable.string(for: "settings.sidebarGroup.app", language: .simplifiedChinese), "应用")
        XCTAssertEqual(L10nTable.string(for: "settings.section.terminal.title", language: .simplifiedChinese), "终端")
        XCTAssertEqual(L10nTable.string(for: "settings.button.cancel", language: .simplifiedChinese), "取消")
        XCTAssertEqual(L10nTable.string(for: "settings.general.language.title", language: .simplifiedChinese), "语言")
        XCTAssertEqual(L10nTable.string(for: "settings.general.language.appliesImmediately", language: .simplifiedChinese), "更改会立即在 Liney 中生效。")
        XCTAssertEqual(L10nTable.string(for: "main.hapi.launchCurrentProject", language: .simplifiedChinese), "在当前项目中启动 HAPI")
        XCTAssertEqual(L10nTable.string(for: "settings.general.terminal.group", language: .simplifiedChinese), "终端")
        XCTAssertEqual(L10nTable.string(for: "settings.general.terminal.useCustomFont", language: .simplifiedChinese), "使用自定义终端字体")
        XCTAssertEqual(L10nTable.string(for: "settings.general.terminal.useCustomFontSize", language: .simplifiedChinese), "使用自定义终端字号")
        XCTAssertEqual(L10nTable.string(for: "settings.general.terminal.previewTitle", language: .simplifiedChinese), "预览")
        XCTAssertEqual(L10nTable.string(for: "settings.sidebar.visibility.group", language: .simplifiedChinese), "侧边栏")
        XCTAssertEqual(L10nTable.string(for: "settings.sidebar.defaultIcons.repository.title", language: .simplifiedChinese), "仓库")
        XCTAssertEqual(L10nTable.string(for: "settings.updates.group", language: .simplifiedChinese), "自动更新")
        XCTAssertEqual(L10nTable.string(for: "settings.updates.checkNow", language: .simplifiedChinese), "立即检查更新")
        XCTAssertEqual(L10nTable.string(for: "settings.shortcuts.intro", language: .simplifiedChinese), "Liney 的快捷键通过应用菜单分发，因此即使终端面板获得焦点时也能继续工作。")
        XCTAssertEqual(L10nTable.string(for: "settings.shortcuts.resetAll", language: .simplifiedChinese), "恢复全部默认值")
        XCTAssertEqual(L10nTable.string(for: "settings.workspace.group", language: .simplifiedChinese), "工作区")
        XCTAssertEqual(L10nTable.string(for: "settings.workspace.runScript", language: .simplifiedChinese), "运行脚本")
        XCTAssertEqual(L10nTable.string(for: "settings.workspace.workflowsHint", language: .simplifiedChinese), "创建可复用的执行方案，把初始化、运行和 agent 启动串联起来。")
        XCTAssertEqual(L10nTable.string(for: "settings.workspace.emptyState", language: .simplifiedChinese), "选择一个工作区以编辑仓库专属设置。")
        XCTAssertEqual(L10nTable.string(for: "settings.workspace.agentPreset.name", language: .simplifiedChinese), "名称")
        XCTAssertEqual(L10nTable.string(for: "settings.workspace.remoteTarget.host", language: .simplifiedChinese), "主机")
        XCTAssertEqual(L10nTable.string(for: "settings.workspace.workflow.localShell", language: .simplifiedChinese), "本地 Shell")
        XCTAssertEqual(L10nTable.string(for: "settings.workspace.workflow.noAgent", language: .simplifiedChinese), "无 agent")
        XCTAssertEqual(L10nTable.string(for: "settings.sidebarAppearance.title", language: .simplifiedChinese), "侧边栏外观")
        XCTAssertEqual(L10nTable.string(for: "settings.sidebarIconEditor.random", language: .simplifiedChinese), "随机")
        XCTAssertEqual(L10nTable.string(for: "settings.sidebarIconCustomization.title", language: .simplifiedChinese), "自定义侧边栏图标")
        XCTAssertEqual(L10nTable.string(for: "settings.shortcuts.category.general", language: .simplifiedChinese), "通用")
        XCTAssertEqual(L10nTable.string(for: "settings.workflow.localSession.reuseFocused", language: .simplifiedChinese), "复用当前焦点")
        XCTAssertEqual(L10nTable.string(for: "settings.workflow.agent.none", language: .simplifiedChinese), "无 agent")
        XCTAssertEqual(L10nTable.string(for: "settings.sidebarIcon.style.solid", language: .simplifiedChinese), "纯色")
        XCTAssertEqual(L10nTable.string(for: "settings.sidebarIcon.palette.blue", language: .simplifiedChinese), "蓝色")
        XCTAssertEqual(L10nTable.string(for: "settings.shortcuts.action.toggleCommandPalette.title", language: .simplifiedChinese), "命令面板")
        XCTAssertEqual(L10nTable.string(for: "settings.shortcuts.action.toggleCommandPalette.subtitle", language: .simplifiedChinese), "搜索并执行工作区动作。")
        XCTAssertEqual(
            L10nTable.string(for: "settings.general.behavior.refreshIntervalHint", language: .simplifiedChinese),
            "控制在启用自动刷新时，Liney 自动刷新仓库和 worktree 状态的频率。最小为 10 秒。"
        )
        XCTAssertEqual(L10nTable.string(for: "settings.shortcuts.action.hideApp.title", language: .simplifiedChinese), "隐藏应用")
        XCTAssertEqual(L10nTable.string(for: "settings.shortcuts.action.minimizeWindow.title", language: .simplifiedChinese), "最小化窗口")
    }

    func testModelAndAppStringsResolveInSimplifiedChinese() {
        XCTAssertEqual(L10nTable.string(for: "workspace.kind.repository", language: .simplifiedChinese), "仓库")
        XCTAssertEqual(L10nTable.string(for: "workspace.kind.localTerminal", language: .simplifiedChinese), "本地终端")
        XCTAssertEqual(L10nTable.string(for: "session.backend.localShell", language: .simplifiedChinese), "本地 Shell")
        XCTAssertEqual(L10nTable.string(for: "activity.kind.workflow", language: .simplifiedChinese), "工作流")
        XCTAssertEqual(L10nTable.string(for: "worktree.main", language: .simplifiedChinese), "主检出")
        XCTAssertEqual(L10nTable.string(for: "worktree.detached", language: .simplifiedChinese), "游离 HEAD")
        XCTAssertEqual(L10nTable.string(for: "canvas.color.slate", language: .simplifiedChinese), "石板灰")
        XCTAssertEqual(L10nTable.string(for: "tab.defaultIndexedFormat", language: .simplifiedChinese), "标签页 %1$ld")
        XCTAssertEqual(L10nTable.string(for: "remote.error.missingTarget", language: .simplifiedChinese), "找不到所选远程目标。")
        XCTAssertEqual(L10nTable.string(for: "remote.activity.openedAgent", language: .simplifiedChinese), "已打开远程 Agent")
        XCTAssertEqual(L10nTable.string(for: "app.about.version.versionOnlyFormat", language: .simplifiedChinese), "版本 %1$@")
        XCTAssertEqual(L10nTable.string(for: "app.about.description", language: .simplifiedChinese), "原生 macOS 终端工作区。")
    }

    func testUpdateSelectedLanguagePostsChangeNotification() {
        let expectation = expectation(forNotification: .lineyLocalizationDidChange, object: nil)

        LocalizationManager.shared.updateSelectedLanguage(.simplifiedChinese)

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(LocalizationManager.shared.selectedLanguage, .simplifiedChinese)
    }
}
