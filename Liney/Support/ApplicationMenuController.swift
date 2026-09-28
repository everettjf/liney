//
//  ApplicationMenuController.swift
//  Liney
//
//  Author: everettjf
//

import AppKit

@MainActor
final class ApplicationMenuController: NSObject, NSMenuDelegate, NSMenuItemValidation {
    private let websiteURL = URL(string: "https://liney.dev")!
    private let feedbackURL = URL(string: "https://github.com/everettjf/liney/issues/new")!
    private let repositoryURL = URL(string: "https://github.com/everettjf/liney")!

    var activeWorkspaceStoreProvider: (() -> WorkspaceStore?)?

    private var dynamicMenus: [ObjectIdentifier: (NSMenu) -> Void] = [:]

    private var shortcutItemsByAction: [LineyShortcutAction: [NSMenuItem]] = [:]

    private func localized(_ key: String) -> String {
        LocalizationManager.shared.string(key)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        l10nFormat(localized(key), locale: Locale.current, arguments: arguments)
    }

    func installMainMenu(appName: String, target: AnyObject, settings: AppSettings) {
        shortcutItemsByAction = [:]
        dynamicMenus = [:]

        let mainMenu = NSMenu(title: "")

        let appMenuItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
        let fileMenuItem = NSMenuItem(title: localized("menu.file"), action: nil, keyEquivalent: "")
        let editMenuItem = NSMenuItem(title: localized("menu.edit"), action: nil, keyEquivalent: "")
        let viewMenuItem = NSMenuItem(title: localized("menu.view"), action: nil, keyEquivalent: "")
        let workspaceMenuItem = NSMenuItem(title: localized("menu.workspace"), action: nil, keyEquivalent: "")
        let windowMenuItem = NSMenuItem(title: localized("menu.window"), action: nil, keyEquivalent: "")
        let helpMenuItem = NSMenuItem(title: localized("menu.help"), action: nil, keyEquivalent: "")

        mainMenu.items = [
            appMenuItem,
            fileMenuItem,
            editMenuItem,
            viewMenuItem,
            workspaceMenuItem,
            windowMenuItem,
            helpMenuItem,
        ]

        let appMenu = NSMenu(title: appName)
        appMenuItem.submenu = appMenu
        let aboutItem = addItem(
            title: localizedFormat("menu.app.aboutFormat", appName),
            action: #selector(AppDelegate.showAboutPanel(_:)),
            keyEquivalent: "",
            to: appMenu
        )
        aboutItem.target = target
        let checkForUpdatesItem = addItem(
            title: localized("menu.app.checkForUpdates"),
            action: #selector(AppDelegate.checkForUpdates(_:)),
            keyEquivalent: "",
            to: appMenu
        )
        checkForUpdatesItem.target = target
        appMenu.addItem(.separator())

        let servicesItem = NSMenuItem(title: localized("menu.app.services"), action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: localized("menu.app.services"))
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)
        NSApp.servicesMenu = servicesMenu

        appMenu.addItem(.separator())
        addShortcutItem(
            title: localizedFormat("menu.app.hideFormat", appName),
            shortcutAction: .hideApp,
            to: appMenu,
            target: target
        )

        addShortcutItem(
            title: localized("menu.app.hideOthers"),
            shortcutAction: .hideOtherApps,
            to: appMenu,
            target: target
        )

        addItem(title: localized("menu.app.showAll"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "", to: appMenu)
        appMenu.addItem(.separator())
        addShortcutItem(title: localized("menu.app.settings"), shortcutAction: .openSettings, to: appMenu, target: target)
        appMenu.addItem(.separator())
        addShortcutItem(
            title: localizedFormat("menu.app.quitFormat", appName),
            shortcutAction: .quitApp,
            to: appMenu,
            target: target
        )

        let fileMenu = NSMenu(title: localized("menu.file"))
        fileMenuItem.submenu = fileMenu
        addShortcutItem(title: localized("menu.file.newWindow"), shortcutAction: .newWindow, to: fileMenu, target: target)
        addShortcutItem(title: localized("menu.file.newTab"), shortcutAction: .newTab, to: fileMenu, target: target)
        addShortcutItem(title: localized("workbench.newTerminal"), shortcutAction: .newStandaloneTerminal, to: fileMenu, target: target)
        if LineyFeatureFlags.showsRemoteSessionCreationUI {
            let remoteItem = addItem(
                title: localized("menu.file.newRemoteWorkspace"),
                action: #selector(newRemoteWorkspace(_:)),
                keyEquivalent: "",
                to: fileMenu
            )
            remoteItem.target = self
        }
        fileMenu.addItem(.separator())
        addShortcutItem(title: localized("menu.file.splitRight"), shortcutAction: .splitRight, to: fileMenu, target: target)
        addShortcutItem(title: localized("menu.file.splitDown"), shortcutAction: .splitDown, to: fileMenu, target: target)
        addShortcutItem(title: localized("menu.file.duplicatePane"), shortcutAction: .duplicatePane, to: fileMenu, target: target)
        fileMenu.addItem(.separator())
        addShortcutItem(title: localized("menu.file.resetTerminal"), shortcutAction: .resetTerminal, to: fileMenu, target: target)
        fileMenu.addItem(.separator())
        addShortcutItem(title: localized("menu.file.closeTab"), shortcutAction: .closeTab, to: fileMenu, target: target)
        addShortcutItem(title: localized("menu.file.closePane"), shortcutAction: .closePane, to: fileMenu, target: target)

        let editMenu = NSMenu(title: localized("menu.edit"))
        editMenuItem.submenu = editMenu
        addShortcutItem(title: localized("menu.edit.undo"), shortcutAction: .undo, to: editMenu, target: target)
        addShortcutItem(title: localized("menu.edit.redo"), shortcutAction: .redo, to: editMenu, target: target)

        editMenu.addItem(.separator())
        addShortcutItem(title: localized("menu.edit.cut"), shortcutAction: .cut, to: editMenu, target: target)
        addShortcutItem(title: localized("menu.edit.copy"), shortcutAction: .copy, to: editMenu, target: target)
        addShortcutItem(title: localized("menu.edit.paste"), shortcutAction: .paste, to: editMenu, target: target)
        addShortcutItem(title: localized("menu.edit.selectAll"), shortcutAction: .selectAll, to: editMenu, target: target)
        editMenu.addItem(.separator())
        addShortcutItem(title: localized("menu.edit.find"), shortcutAction: .find, to: editMenu, target: target)
        addShortcutItem(title: localized("menu.edit.findNext"), shortcutAction: .findNext, to: editMenu, target: target)
        addShortcutItem(title: localized("menu.edit.findPrevious"), shortcutAction: .findPrevious, to: editMenu, target: target)
        addShortcutItem(title: localized("menu.edit.hideFind"), shortcutAction: .hideFind, to: editMenu, target: target)

        let viewMenu = NSMenu(title: localized("menu.view"))
        viewMenuItem.submenu = viewMenu
        addShortcutItem(title: localized("menu.view.toggleSidebar"), shortcutAction: .toggleSidebar, to: viewMenu, target: target)
        addShortcutItem(title: localized("menu.view.commandPalette"), shortcutAction: .toggleCommandPalette, to: viewMenu, target: target)
        addShortcutItem(title: localized("menu.view.workspaceOverview"), shortcutAction: .toggleOverview, to: viewMenu, target: target)
        addShortcutItem(title: localized("menu.view.openOrchestration"), shortcutAction: .openOrchestration, to: viewMenu, target: target)
        viewMenu.addItem(.separator())
        addShortcutItem(title: localized("terminal.menu.previousPrompt"), shortcutAction: .previousTerminalPrompt, to: viewMenu, target: target)
        addShortcutItem(title: localized("terminal.menu.nextPrompt"), shortcutAction: .nextTerminalPrompt, to: viewMenu, target: target)
        addShortcutItem(title: localized("terminal.action.returnToLatest"), shortcutAction: .scrollTerminalToBottom, to: viewMenu, target: target)
        viewMenu.addItem(.separator())
        addShortcutItem(title: localized("menu.view.enterFullScreen"), shortcutAction: .enterFullScreen, to: viewMenu, target: target)

        addManagedItem("main.toolbar.toggleFileTree", action: #selector(toggleFileTree(_:)), to: viewMenu)
        addManagedItem("main.canvas.title", action: #selector(toggleCanvas(_:)), to: viewMenu)

        let workspaceMenu = NSMenu(title: localized("menu.workspace"))
        workspaceMenuItem.submenu = workspaceMenu
        addShortcutItem(title: localized("menu.workspace.refreshSelected"), shortcutAction: .refreshSelectedWorkspace, to: workspaceMenu, target: target)
        addShortcutItem(title: localized("menu.workspace.refreshAll"), shortcutAction: .refreshAllRepositories, to: workspaceMenu, target: target)
        workspaceMenu.addItem(.separator())
        addShortcutItem(title: localized("menu.workspace.nextWorkspace"), shortcutAction: .nextWorkspace, to: workspaceMenu, target: target)
        addShortcutItem(title: localized("menu.workspace.previousWorkspace"), shortcutAction: .previousWorkspace, to: workspaceMenu, target: target)

        workspaceMenu.addItem(.separator())
        addManagedItem("sidebar.menu.createWorktree", action: #selector(createWorktree(_:)), to: workspaceMenu)
        addManagedItem("sidebar.menu.fetchRemotes", action: #selector(fetchRepository(_:)), to: workspaceMenu)
        addShortcutItem(title: localized("menu.view.openDiff"), shortcutAction: .openDiff, to: workspaceMenu, target: target)
        addManagedItem("menu.workspace.openReview", action: #selector(openReview(_:)), to: workspaceMenu)
        addShortcutItem(title: localized("menu.view.openHistory"), shortcutAction: .openHistory, to: workspaceMenu, target: target)
        workspaceMenu.addItem(.separator())
        addDynamicMenu("main.toolbar.chooseWorkflow", to: workspaceMenu) { [weak self] menu in
            guard let store = self?.activeWorkspaceStoreProvider?(), let workspace = store.selectedWorkspace else { return }
            for workflow in workspace.workflows {
                menu.addItem(MenuAction.item(title: workflow.name) { [weak store] in
                    store?.dispatch(.runWorkflow(workspace.id, workflow.id))
                })
            }
            menu.addItem(.separator())
            menu.addItem(MenuAction.item(title: self?.localized("main.workflows.editWorkflows") ?? "") { [weak store] in
                store?.presentWorkflowEditor(for: workspace)
            })
        }
        addDynamicMenu("main.toolbar.chooseExternalEditor", to: workspaceMenu) { [weak self] menu in
            guard let store = self?.activeWorkspaceStoreProvider?(), store.selectedWorkspace != nil else { return }
            for editor in store.availableExternalEditors {
                menu.addItem(MenuAction.item(title: editor.editor.displayName) { [weak store] in
                    store?.openSelectedWorkspaceInExternalEditor(editor.editor)
                })
            }
            if menu.items.isEmpty {
                let item = NSMenuItem(title: self?.localized("main.externalEditor.noneFound") ?? "", action: nil, keyEquivalent: "")
                menu.addItem(item)
            }
        }
        addManagedItem("sidebar.menu.workspaceSettings", action: #selector(workspaceSettings(_:)), to: workspaceMenu)

        addDynamicMenu("main.sleepPrevention.status", to: appMenu) { [weak self] menu in
            guard let store = self?.activeWorkspaceStoreProvider?() else { return }
            let source = SleepPreventionMenu.make(for: store)
            for item in source.items {
                source.removeItem(item)
                menu.addItem(item)
            }
        }
        // Keep the global utility above Quit, not below it.
        if let item = appMenu.items.last {
            appMenu.removeItem(item)
            appMenu.insertItem(item, at: appMenu.items.count - 2)
        }

        let windowMenu = NSMenu(title: localized("menu.window"))
        windowMenuItem.submenu = windowMenu
        addShortcutItem(title: localized("menu.window.minimize"), shortcutAction: .minimizeWindow, to: windowMenu, target: target)
        addItem(title: localized("menu.window.zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "", to: windowMenu)
        addShortcutItem(title: localized("menu.window.closeWindow"), shortcutAction: .closeWindow, to: windowMenu, target: target)
        windowMenu.addItem(.separator())
        addItem(title: localized("menu.window.showTabBar"), action: #selector(NSWindow.toggleTabBar(_:)), keyEquivalent: "", to: windowMenu)
        addItem(title: localized("menu.window.moveTabToNewWindow"), action: #selector(NSWindow.moveTabToNewWindow(_:)), keyEquivalent: "", to: windowMenu)
        addItem(title: localized("menu.window.mergeAllWindows"), action: #selector(NSWindow.mergeAllWindows(_:)), keyEquivalent: "", to: windowMenu)
        windowMenu.addItem(.separator())
        addItem(title: localized("menu.window.bringAllToFront"), action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "", to: windowMenu)
        windowMenu.addItem(.separator())
        addShortcutItem(title: localized("menu.view.nextTab"), shortcutAction: .nextTab, to: windowMenu, target: target)
        addShortcutItem(title: localized("menu.view.previousTab"), shortcutAction: .previousTab, to: windowMenu, target: target)
        for index in 1...9 {
            let item = addShortcutItem(
                title: localizedFormat("menu.view.selectTabFormat", index),
                shortcutAction: .selectTabByNumber,
                to: windowMenu,
                target: target
            )
            item.tag = index
        }
        windowMenu.addItem(.separator())
        addShortcutItem(title: localized("menu.view.focusPaneLeft"), shortcutAction: .focusPaneLeft, to: windowMenu, target: target)
        addShortcutItem(title: localized("menu.view.focusPaneRight"), shortcutAction: .focusPaneRight, to: windowMenu, target: target)
        addShortcutItem(title: localized("menu.view.focusPaneUp"), shortcutAction: .focusPaneUp, to: windowMenu, target: target)
        addShortcutItem(title: localized("menu.view.focusPaneDown"), shortcutAction: .focusPaneDown, to: windowMenu, target: target)
        NSApp.windowsMenu = windowMenu

        let helpMenu = NSMenu(title: localized("menu.help"))
        helpMenuItem.submenu = helpMenu
        let diagnosticsItem = addItem(
            title: localized("menu.help.terminalDiagnostics"),
            action: #selector(AppDelegate.showTerminalDiagnostics(_:)),
            keyEquivalent: "",
            to: helpMenu
        )
        diagnosticsItem.target = target
        helpMenu.addItem(.separator())
        addItem(title: localized("menu.help.visitWebsite"), action: #selector(openWebsite(_:)), keyEquivalent: "", to: helpMenu)
        addItem(title: localized("menu.help.starSourceCode"), action: #selector(openRepository(_:)), keyEquivalent: "", to: helpMenu)
        addItem(title: localized("menu.help.submitFeedback"), action: #selector(submitFeedback(_:)), keyEquivalent: "", to: helpMenu)
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = mainMenu
        applySettings(settings)
    }

    private func addManagedItem(_ key: String, action: Selector, to menu: NSMenu) {
        let item = addItem(title: localized(key), action: action, keyEquivalent: "", to: menu)
        item.target = self
    }

    private func addDynamicMenu(_ key: String, to parent: NSMenu, build: @escaping (NSMenu) -> Void) {
        let item = NSMenuItem(title: localized(key), action: nil, keyEquivalent: "")
        let menu = NSMenu(title: item.title)
        menu.delegate = self
        dynamicMenus[ObjectIdentifier(menu)] = build
        item.submenu = menu
        parent.addItem(item)
        parent.delegate = self
        menuNeedsUpdate(menu)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let build = dynamicMenus[ObjectIdentifier(menu)] else {
            for item in menu.items {
                if let submenu = item.submenu, dynamicMenus[ObjectIdentifier(submenu)] != nil {
                    menuNeedsUpdate(submenu)
                }
            }
            return
        }
        menu.removeAllItems()
        build(menu)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let store = activeWorkspaceStoreProvider?()
        let workspace = store?.selectedWorkspace
        switch item.action {
        case #selector(toggleFileTree(_:)):
            item.state = workspace?.isFileTreePresented == true ? .on : .off
            return workspace != nil
        case #selector(toggleCanvas(_:)):
            item.state = store?.isCanvasPresented == true ? .on : .off
            return store != nil
        case #selector(createWorktree(_:)), #selector(fetchRepository(_:)):
            return workspace?.supportsLocalRepositoryFeatures == true
        case #selector(openReview(_:)):
            return workspace?.supportsRepositoryFeatures == true
        case #selector(workspaceSettings(_:)):
            return workspace != nil
        default:
            return true
        }
    }

    @objc private func toggleFileTree(_ sender: Any?) {
        activeWorkspaceStoreProvider?()?.selectedWorkspace?.toggleFileTree()
    }

    @objc private func toggleCanvas(_ sender: Any?) {
        guard let store = activeWorkspaceStoreProvider?() else { return }
        store.isOverviewPresented = false
        store.isCanvasPresented.toggle()
        if !store.isCanvasPresented, let workspace = store.selectedWorkspace,
           let paneID = workspace.sessionController.focusedPaneID {
            DispatchQueue.main.async { workspace.sessionController.focus(paneID) }
        }
    }

    @objc private func createWorktree(_ sender: Any?) {
        guard let store = activeWorkspaceStoreProvider?(), let workspace = store.selectedWorkspace,
              workspace.supportsLocalRepositoryFeatures else { return }
        store.presentCreateWorktree(for: workspace)
    }

    @objc private func fetchRepository(_ sender: Any?) {
        guard let store = activeWorkspaceStoreProvider?(), let workspace = store.selectedWorkspace,
              workspace.supportsLocalRepositoryFeatures else { return }
        store.fetch(workspace)
    }

    @objc private func openReview(_ sender: Any?) {
        guard let workspace = activeWorkspaceStoreProvider?()?.selectedWorkspace,
              workspace.supportsRepositoryFeatures else { return }
        ReviewWindowManager.shared.show(repositoryPath: workspace.activeWorktreePath, repositoryName: workspace.name)
    }

    @objc private func workspaceSettings(_ sender: Any?) {
        guard let store = activeWorkspaceStoreProvider?(), let workspace = store.selectedWorkspace else { return }
        store.presentSettings(for: workspace)
    }

    func applySettings(_ settings: AppSettings) {
        for action in LineyShortcutAction.allCases {
            guard let items = shortcutItemsByAction[action] else { continue }

            if action == .selectTabByNumber {
                let shortcut = LineyKeyboardShortcuts.effectiveShortcut(for: action, in: settings)
                for item in items {
                    guard let shortcut else {
                        clearShortcut(on: item)
                        continue
                    }
                    applyShortcut(shortcut.withKey("\(item.tag)"), to: item)
                }
                continue
            }

            let shortcut = LineyKeyboardShortcuts.effectiveShortcut(for: action, in: settings)
            for item in items {
                guard let shortcut else {
                    clearShortcut(on: item)
                    continue
                }
                applyShortcut(shortcut, to: item)
            }
        }
    }

    @objc private func openWebsite(_ sender: Any?) {
        NSWorkspace.shared.open(websiteURL)
    }

    @objc private func submitFeedback(_ sender: Any?) {
        NSWorkspace.shared.open(feedbackURL)
    }

    @objc private func openRepository(_ sender: Any?) {
        NSWorkspace.shared.open(repositoryURL)
    }

    @objc private func newRemoteWorkspace(_ sender: Any?) {
        activeWorkspaceStoreProvider?()?.presentConnectSSH()
    }

    @discardableResult
    private func addItem(title: String, action: Selector?, keyEquivalent: String, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        if action == #selector(openWebsite(_:)) || action == #selector(submitFeedback(_:)) || action == #selector(openRepository(_:)) || action == #selector(newRemoteWorkspace(_:)) {
            item.target = self
        }
        menu.addItem(item)
        return item
    }

    @discardableResult
    private func addShortcutItem(
        title: String,
        shortcutAction: LineyShortcutAction,
        to menu: NSMenu,
        target: AnyObject
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(AppDelegate.performShortcutAction(_:)), keyEquivalent: "")
        item.target = target
        item.representedObject = shortcutAction.rawValue
        menu.addItem(item)
        shortcutItemsByAction[shortcutAction, default: []].append(item)
        return item
    }

    private func applyShortcut(_ shortcut: StoredShortcut, to item: NSMenuItem) {
        guard let keyEquivalent = shortcut.menuItemKeyEquivalent else {
            clearShortcut(on: item)
            return
        }
        item.keyEquivalent = keyEquivalent
        item.keyEquivalentModifierMask = shortcut.modifierFlags
    }

    private func clearShortcut(on item: NSMenuItem) {
        item.keyEquivalent = ""
        item.keyEquivalentModifierMask = []
    }
}


/// Retain the action with the menu item because NSMenuItem's target is weak.
@MainActor
private final class MenuAction: NSObject {
    private let action: () -> Void
    private init(_ action: @escaping () -> Void) { self.action = action }
    @objc private func invoke(_ sender: Any?) { action() }

    static func item(title: String, action: @escaping () -> Void) -> NSMenuItem {
        let handler = MenuAction(action)
        let item = NSMenuItem(title: title, action: #selector(invoke(_:)), keyEquivalent: "")
        item.target = handler
        item.representedObject = handler
        return item
    }
}

@MainActor
enum SleepPreventionMenu {
    static func make(for store: WorkspaceStore) -> NSMenu {
        let menu = NSMenu()
        func localized(_ key: String) -> String { LocalizationManager.shared.string(key) }
        if let session = store.sleepPreventionSession {
            let status = NSMenuItem(title: "\(session.mode.title) · \(session.remainingDescription(relativeTo: Date()))", action: nil, keyEquivalent: "")
            menu.addItem(status)
            menu.addItem(MenuAction.item(title: localized("main.sleepPrevention.stop")) { [weak store] in
                store?.stopSleepPrevention()
            })
            menu.addItem(.separator())
        }
        for mode in SleepPreventionMode.allCases {
            let item = NSMenuItem(title: mode.title, action: nil, keyEquivalent: "")
            item.state = store.sleepPreventionSession?.mode == mode ? .on : .off
            item.toolTip = localized(mode == .sleep ? "main.sleepPrevention.mode.sleep.help" : "main.sleepPrevention.mode.sleepAndLock.help")
            let durations = NSMenu()
            for option in SleepPreventionDurationOption.allCases {
                let duration = MenuAction.item(title: option.title) { [weak store] in
                    store?.activateSleepPrevention(option, mode: mode)
                }
                duration.state = store.sleepPreventionSession?.mode == mode && store.sleepPreventionSession?.option == option ? .on : .off
                durations.addItem(duration)
            }
            item.submenu = durations
            menu.addItem(item)
        }
        return menu
    }
}
