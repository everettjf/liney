//
//  ApplicationMenuController.swift
//  Liney
//
//  Author: everettjf
//

import AppKit

@MainActor
final class ApplicationMenuController: NSObject {
    private let websiteURL = URL(string: "https://liney.dev")!
    private let feedbackURL = URL(string: "https://github.com/everettjf/liney/issues/new")!
    private let repositoryURL = URL(string: "https://github.com/everettjf/liney")!

    private var shortcutItemsByAction: [LineyShortcutAction: [NSMenuItem]] = [:]

    func installMainMenu(appName: String, target: AnyObject, settings: AppSettings) {
        shortcutItemsByAction = [:]

        let mainMenu = NSMenu(title: "")

        let appMenuItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
        let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let viewMenuItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        let workspaceMenuItem = NSMenuItem(title: "Workspace", action: nil, keyEquivalent: "")
        let windowMenuItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let helpMenuItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")

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
        let aboutItem = addItem(title: "About \(appName)", action: #selector(AppDelegate.showAboutPanel(_:)), keyEquivalent: "", to: appMenu)
        aboutItem.target = target
        let checkForUpdatesItem = addItem(title: "Check for Updates...", action: #selector(AppDelegate.checkForUpdates(_:)), keyEquivalent: "", to: appMenu)
        checkForUpdatesItem.target = target
        appMenu.addItem(.separator())

        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)
        NSApp.servicesMenu = servicesMenu

        appMenu.addItem(.separator())
        addItem(title: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h", to: appMenu)

        let hideOthersItem = addItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h",
            to: appMenu
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]

        addItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "", to: appMenu)
        appMenu.addItem(.separator())
        addShortcutItem(title: "Settings...", shortcutAction: .openSettings, to: appMenu, target: target)
        appMenu.addItem(.separator())
        addItem(title: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q", to: appMenu)

        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu
        addShortcutItem(title: "New Window", shortcutAction: .newWindow, to: fileMenu, target: target)
        addShortcutItem(title: "New Tab", shortcutAction: .newTab, to: fileMenu, target: target)
        fileMenu.addItem(.separator())
        addShortcutItem(title: "Split Right", shortcutAction: .splitRight, to: fileMenu, target: target)
        addShortcutItem(title: "Split Down", shortcutAction: .splitDown, to: fileMenu, target: target)
        addShortcutItem(title: "Duplicate Pane", shortcutAction: .duplicatePane, to: fileMenu, target: target)
        fileMenu.addItem(.separator())
        addShortcutItem(title: "Close Tab", shortcutAction: .closeTab, to: fileMenu, target: target)
        addShortcutItem(title: "Close Pane", shortcutAction: .closePane, to: fileMenu, target: target)

        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        addItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z", to: editMenu)

        let redoItem = addItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z", to: editMenu)
        redoItem.keyEquivalentModifierMask = [.command, .shift]

        editMenu.addItem(.separator())
        addItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x", to: editMenu)
        addItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c", to: editMenu)
        addItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v", to: editMenu)
        addItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a", to: editMenu)
        editMenu.addItem(.separator())
        addItem(title: "Find", action: #selector(NSResponder.performTextFinderAction(_:)), keyEquivalent: "f", to: editMenu).tag = NSTextFinder.Action.showFindInterface.rawValue
        let findNextItem = addItem(title: "Find Next", action: #selector(NSResponder.performTextFinderAction(_:)), keyEquivalent: "g", to: editMenu)
        findNextItem.tag = NSTextFinder.Action.nextMatch.rawValue
        let findPreviousItem = addItem(title: "Find Previous", action: #selector(NSResponder.performTextFinderAction(_:)), keyEquivalent: "G", to: editMenu)
        findPreviousItem.keyEquivalentModifierMask = [.command, .shift]
        findPreviousItem.tag = NSTextFinder.Action.previousMatch.rawValue
        addItem(title: "Hide Find", action: #selector(NSResponder.performTextFinderAction(_:)), keyEquivalent: "e", to: editMenu).tag = NSTextFinder.Action.hideFindInterface.rawValue

        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu
        addShortcutItem(title: "Toggle Sidebar", shortcutAction: .toggleSidebar, to: viewMenu, target: target)
        addShortcutItem(title: "Command Palette", shortcutAction: .toggleCommandPalette, to: viewMenu, target: target)
        addShortcutItem(title: "Workspace Overview", shortcutAction: .toggleOverview, to: viewMenu, target: target)
        addShortcutItem(title: "Open Diff", shortcutAction: .openDiff, to: viewMenu, target: target)
        viewMenu.addItem(.separator())
        addShortcutItem(title: "Next Tab", shortcutAction: .nextTab, to: viewMenu, target: target)
        addShortcutItem(title: "Previous Tab", shortcutAction: .previousTab, to: viewMenu, target: target)
        for index in 1...9 {
            let item = addShortcutItem(
                title: "Select Tab \(index)",
                shortcutAction: .selectTabByNumber,
                to: viewMenu,
                target: target
            )
            item.tag = index
        }
        viewMenu.addItem(.separator())
        addShortcutItem(title: "Focus Pane Left", shortcutAction: .focusPaneLeft, to: viewMenu, target: target)
        addShortcutItem(title: "Focus Pane Right", shortcutAction: .focusPaneRight, to: viewMenu, target: target)
        addShortcutItem(title: "Focus Pane Up", shortcutAction: .focusPaneUp, to: viewMenu, target: target)
        addShortcutItem(title: "Focus Pane Down", shortcutAction: .focusPaneDown, to: viewMenu, target: target)
        viewMenu.addItem(.separator())
        addShortcutItem(title: "Enter Full Screen", shortcutAction: .enterFullScreen, to: viewMenu, target: target)

        let workspaceMenu = NSMenu(title: "Workspace")
        workspaceMenuItem.submenu = workspaceMenu
        addShortcutItem(title: "Refresh Selected Workspace", shortcutAction: .refreshSelectedWorkspace, to: workspaceMenu, target: target)
        addShortcutItem(title: "Refresh All Repositories", shortcutAction: .refreshAllRepositories, to: workspaceMenu, target: target)

        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        addItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m", to: windowMenu)
        addItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "", to: windowMenu)
        addShortcutItem(title: "Close Window", shortcutAction: .closeWindow, to: windowMenu, target: target)
        windowMenu.addItem(.separator())
        addItem(title: "Show Tab Bar", action: #selector(NSWindow.toggleTabBar(_:)), keyEquivalent: "", to: windowMenu)
        addItem(title: "Move Tab to New Window", action: #selector(NSWindow.moveTabToNewWindow(_:)), keyEquivalent: "", to: windowMenu)
        addItem(title: "Merge All Windows", action: #selector(NSWindow.mergeAllWindows(_:)), keyEquivalent: "", to: windowMenu)
        windowMenu.addItem(.separator())
        addItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "", to: windowMenu)
        NSApp.windowsMenu = windowMenu

        let helpMenu = NSMenu(title: "Help")
        helpMenuItem.submenu = helpMenu
        addItem(title: "Visit liney.dev", action: #selector(openWebsite(_:)), keyEquivalent: "", to: helpMenu)
        addItem(title: "Star Source Code", action: #selector(openRepository(_:)), keyEquivalent: "", to: helpMenu)
        addItem(title: "Submit Feedback", action: #selector(submitFeedback(_:)), keyEquivalent: "", to: helpMenu)
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = mainMenu
        applySettings(settings)
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

    @discardableResult
    private func addItem(title: String, action: Selector?, keyEquivalent: String, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        if action == #selector(openWebsite(_:)) || action == #selector(submitFeedback(_:)) || action == #selector(openRepository(_:)) {
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
