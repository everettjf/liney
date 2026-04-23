//
//  AppDelegate.swift
//  Liney
//
//  Author: everettjf
//

import Cocoa
import GhosttyKit
import Sentry

private func lineyLocalizedAppString(_ key: String) -> String {
    LocalizationManager.shared.string(key)
}

private func lineyLocalizedAppFormat(_ key: String, _ arguments: CVarArg...) -> String {
    l10nFormat(lineyLocalizedAppString(key), locale: .current, arguments: arguments)
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let websiteURL = URL(string: "https://liney.dev")!
    private let repositoryURL = URL(string: "https://github.com/everettjf/liney")!
    private let quitConfirmationSuppressionInterval: TimeInterval = 0.5

    @MainActor private var desktopApplication: LineyDesktopApplication?
    @MainActor private let applicationMenuController = ApplicationMenuController()
    private var appSettingsObserver: NSObjectProtocol?
    private var localizationObserver: NSObjectProtocol?
    private var isPresentingQuitConfirmation = false
    private var suppressQuitConfirmationUntil: Date?
    @MainActor private var pendingIncomingURLs: [URL] = []
    @MainActor private var isReadyToHandleURLs = false

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        if lineyIsRunningTests() {
            return
        }

        let releaseVersion = applicationReleaseVersion()

        SentrySDK.start { options in
            // sentry id
            options.dsn = "https://d2856035f52ef60d4ae74f88e0194793@o4510180697636864.ingest.us.sentry.io/4511085450297344"
            
            // version marker
            options.releaseName = "liney-\(releaseVersion)"
            print("release name : \(options.releaseName ?? "<null>")")
            
            // no need to debug
            // options.debug = true // Enabling debug when first installing is always helpful

            // No Pii information
            options.sendDefaultPii = false
            
            // just get session
            options.enableAutoSessionTracking = true
            
            // disable hang detect now
            options.enableAppHangTracking = false
        }
        
        // record app launch only
        SentrySDK.metrics.count(key: "app.launch", value: 1)
        
        Task { @MainActor in
            let desktopApplication = LineyDesktopApplication()
            self.desktopApplication = desktopApplication
            self.applicationMenuController.activeWorkspaceStoreProvider = { [weak self] in
                self?.desktopApplication?.activeWorkspaceStore
            }
            appSettingsObserver = NotificationCenter.default.addObserver(
                forName: .lineyAppSettingsDidChange,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self,
                      let settings = notification.object as? AppSettings else {
                    return
                }
                Task { @MainActor in
                    self.applicationMenuController.applySettings(settings)
                    self.desktopApplication?.updateHotKeyWindowSettings(settings)
                    if settings.dynamicIslandEnabled {
                        IslandPanelController.shared.workspaceStore = self.desktopApplication?.activeWorkspaceStore
                        IslandPanelController.shared.show()
                    } else {
                        IslandPanelController.shared.hide()
                    }
                }
            }
            localizationObserver = NotificationCenter.default.addObserver(
                forName: .lineyLocalizationDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.refreshMainMenu()
                }
            }
            WorkspaceNotificationCenter.shared.onNotificationTapped = { [weak desktopApplication] workspaceID, worktreePath in
                desktopApplication?.navigateToWorkspace(id: workspaceID, worktreePath: worktreePath)
            }
            WorkspaceNotificationCenter.shared.onNotificationTappedFromSystem = {
                let island = IslandPanelController.shared
                let state = island.state
                state.selectedTab = .notifications
                state.isExpanded = true
                island.show()
                island.repositionPanel()
            }
            desktopApplication.launch()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.refreshMainMenu()
                if let store = self.desktopApplication?.activeWorkspaceStore {
                    IslandPanelController.shared.workspaceStore = store
                    if store.appSettings.dynamicIslandEnabled {
                        IslandPanelController.shared.show()
                    }
                }
                self.drainPendingIncomingURLs()
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            if self.isReadyToHandleURLs {
                for url in urls {
                    await self.handleIncomingURL(url)
                }
            } else {
                self.pendingIncomingURLs.append(contentsOf: urls)
            }
        }
    }

    @MainActor
    private func drainPendingIncomingURLs() {
        isReadyToHandleURLs = true
        let pending = pendingIncomingURLs
        pendingIncomingURLs.removeAll()
        Task { @MainActor in
            for url in pending {
                await handleIncomingURL(url)
            }
        }
    }

    @MainActor
    private func handleIncomingURL(_ url: URL) async {
        guard let request = LineyURLScheme.parseRunURL(url) else {
            NSLog("[Liney URL] Ignoring unsupported URL: %@", url.absoluteString)
            return
        }

        guard LineyURLScheme.isEnabled() else {
            NSLog("[Liney URL] URL scheme is disabled in Settings, rejecting request")
            presentURLSchemeAlert(
                title: lineyLocalizedAppString("urlScheme.rejected.title"),
                message: lineyLocalizedAppString("urlScheme.rejected.disabled")
            )
            return
        }

        guard let storedToken = LineyURLScheme.storedToken() else {
            NSLog("[Liney URL] URL scheme is enabled but no token is configured, rejecting request")
            presentURLSchemeAlert(
                title: lineyLocalizedAppString("urlScheme.rejected.title"),
                message: lineyLocalizedAppString("urlScheme.rejected.noToken")
            )
            return
        }

        guard request.token == storedToken else {
            NSLog("[Liney URL] Token mismatch, rejecting request")
            presentURLSchemeAlert(
                title: lineyLocalizedAppString("urlScheme.rejected.title"),
                message: lineyLocalizedAppString("urlScheme.rejected.tokenMismatch")
            )
            return
        }

        if !LineyURLScheme.skipConfirmation() {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = lineyLocalizedAppString("urlScheme.confirm.title")
            alert.informativeText = lineyLocalizedAppFormat("urlScheme.confirm.bodyFormat", request.cmd, request.cwd)
            alert.addButton(withTitle: lineyLocalizedAppString("urlScheme.confirm.run"))
            alert.addButton(withTitle: lineyLocalizedAppString("urlScheme.confirm.cancel"))
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        await executeLineyRunRequest(request)
    }

    @MainActor
    private func executeLineyRunRequest(_ request: LineyURLScheme.RunRequest) async {
        desktopApplication?.reopenMainWindow()

        guard let store = desktopApplication?.activeWorkspaceStore else {
            presentURLSchemeAlert(
                title: lineyLocalizedAppString("urlScheme.error.title"),
                message: lineyLocalizedAppString("urlScheme.error.noWorkspace")
            )
            return
        }

        // Always route URL-scheme commands into the default "Terminal" local
        // workspace at $HOME. Normally that workspace is hidden once the user
        // opens other folders; we re-create and select it here so the pane is
        // visible. The pane itself still runs in the requested cwd.
        let workspace = store.ensureAndSelectDefaultLocalWorkspace()

        let configuration = AgentSessionConfiguration(
            name: "Liney Run",
            launchPath: "/bin/sh",
            arguments: ["-c", request.cmd],
            environment: [:],
            workingDirectory: request.cwd
        )

        store.createSession(
            in: workspace,
            backendConfiguration: .agent(configuration),
            workingDirectory: request.cwd,
            splitAxis: .vertical
        )
    }

    @MainActor
    private func presentURLSchemeAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: lineyLocalizedAppString("urlScheme.alert.ok"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        if let appSettingsObserver {
            NotificationCenter.default.removeObserver(appSettingsObserver)
            self.appSettingsObserver = nil
        }
        if let localizationObserver {
            NotificationCenter.default.removeObserver(localizationObserver)
            self.localizationObserver = nil
        }
        guard Thread.isMainThread else { return }
        MainActor.assumeIsolated {
            desktopApplication?.shutdown()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        guard Thread.isMainThread else { return true }
        return MainActor.assumeIsolated {
            lineyShouldTerminateAfterLastWindowClosed(
                hotKeyWindowEnabled: desktopApplication?.isHotKeyWindowEnabled ?? false,
                isRunningTests: lineyIsRunningTests()
            )
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard Thread.isMainThread else { return .terminateNow }
        return MainActor.assumeIsolated {
            if isPresentingQuitConfirmation {
                return .terminateCancel
            }
            if let suppressQuitConfirmationUntil, suppressQuitConfirmationUntil > Date() {
                return .terminateCancel
            }

            let needsConfirmQuit = desktopApplication?.needsConfirmQuit ?? false
            let shouldConfirm = lineyShouldConfirmTermination(
                confirmQuitWhenCommandsRunning: desktopApplication?.confirmQuitWhenCommandsRunning ?? true,
                needsConfirmQuit: needsConfirmQuit
            )
            guard shouldConfirm else { return .terminateNow }

            let sessionCount = max(
                desktopApplication?.quitConfirmationSessionCount ?? 0,
                needsConfirmQuit ? 1 : 0
            )
            let copy = lineyQuitConfirmationCopy(quitConfirmationSessionCount: sessionCount)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = copy.title
            alert.informativeText = copy.message
            alert.addButton(withTitle: lineyLocalizedAppString("app.quit.confirm"))
            alert.addButton(withTitle: lineyLocalizedAppString("app.quit.cancel"))
            NSApp.activate(ignoringOtherApps: true)
            isPresentingQuitConfirmation = true
            defer { isPresentingQuitConfirmation = false }

            if alert.runModal() == .alertFirstButtonReturn {
                suppressQuitConfirmationUntil = nil
                return .terminateNow
            }

            suppressQuitConfirmationUntil = Date().addingTimeInterval(quitConfirmationSuppressionInterval)
            return .terminateCancel
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard Thread.isMainThread else { return false }
        return MainActor.assumeIsolated {
            guard lineyShouldReopenMainWindow(hasVisibleWindows: flag) else {
                // macOS counts a minimized window as "visible" here, so
                // hasVisibleWindows is true whenever the window is docked.
                // AppKit's default reopen then does nothing and the user is
                // stuck clicking the Dock icon with no effect — explicitly
                // deminiaturize so Dock-click restores the window reliably.
                var restored = false
                for window in NSApp.windows where window.isMiniaturized {
                    window.deminiaturize(nil)
                    restored = true
                }
                if restored {
                    NSApp.activate(ignoringOtherApps: true)
                }
                return restored
            }
            desktopApplication?.reopenMainWindow()
            return true
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    @objc func openSettings(_ sender: Any?) {
        Task { @MainActor in
            desktopApplication?.presentSettings()
        }
    }

    @objc func showAboutPanel(_ sender: Any?) {
        let appName = applicationName()
        let aboutOptions: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: appName,
            .applicationVersion: formattedApplicationVersion(),
            .credits: aboutCredits(),
        ]
        NSApp.orderFrontStandardAboutPanel(options: aboutOptions)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func checkForUpdates(_ sender: Any?) {
        Task { @MainActor in
            desktopApplication?.checkForUpdates()
        }
    }

    @objc func toggleCommandPalette(_ sender: Any?) {
        Task { @MainActor in
            desktopApplication?.toggleCommandPalette()
        }
    }

    @objc func newTab(_ sender: Any?) {
        Task { @MainActor in
            desktopApplication?.createTabInSelectedWorkspace()
        }
    }

    @objc func selectNextTab(_ sender: Any?) {
        Task { @MainActor in
            desktopApplication?.selectNextTab()
        }
    }

    @objc func selectPreviousTab(_ sender: Any?) {
        Task { @MainActor in
            desktopApplication?.selectPreviousTab()
        }
    }

    @objc func selectTabNumber(_ sender: NSMenuItem) {
        Task { @MainActor in
            desktopApplication?.selectTab(number: sender.tag)
        }
    }

    @objc func performShortcutAction(_ sender: NSMenuItem) {
        guard let shortcutAction = shortcutAction(for: sender) else { return }

        Task { @MainActor in
            self.performShortcutAction(shortcutAction, tabNumber: sender.tag)
        }
    }

    @MainActor
    func performShortcutAction(matching event: NSEvent) -> Bool {
        guard let desktopApplication else {
            return false
        }

        if let match = lineyShortcutMatch(for: event, in: desktopApplication.currentAppSettings) {
            performShortcutAction(match.action, tabNumber: match.tabNumber ?? 0)
            return true
        }

        if let preset = lineyQuickCommandMatch(for: event, in: desktopApplication.currentAppSettings) {
            desktopApplication.insertQuickCommand(preset)
            return true
        }

        return false
    }

    private func canPerformResponderAction(_ selector: Selector, sender: Any?) -> Bool {
        NSApp.target(forAction: selector, to: nil, from: sender) != nil
    }

    private func dispatchResponderAction(_ selector: Selector, sender: Any?) {
        NSApp.sendAction(selector, to: nil, from: sender)
    }


    @MainActor
    func shouldDispatchGhosttySplitAction(_ direction: ghostty_action_split_direction_e) -> Bool {
        guard let desktopApplication else { return true }
        return lineyGhosttyShouldDispatchWorkspaceSplitAction(
            direction,
            settings: desktopApplication.currentAppSettings
        )
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let desktopApplication else { return false }

        switch menuItem.action {
        case #selector(newTab(_:)):
            return desktopApplication.hasSelectedWorkspace
        case #selector(selectNextTab(_:)), #selector(selectPreviousTab(_:)):
            return desktopApplication.selectedWorkspaceTabCount > 1
        case #selector(selectTabNumber(_:)):
            return menuItem.tag >= 1 && menuItem.tag <= desktopApplication.selectedWorkspaceTabCount
        case #selector(performShortcutAction(_:)):
            guard let shortcutAction = shortcutAction(for: menuItem) else { return false }
            switch shortcutAction {
            case .hideApp,
                 .hideOtherApps,
                 .quitApp,
                 .newWindow,
                 .openSettings,
                 .toggleCommandPalette,
                 .toggleSidebar,
                 .toggleOverview,
                 .openDiff,
                 .openHistory:
                return true
            case .undo:
                return canPerformResponderAction(Selector(("undo:")), sender: menuItem)
            case .redo:
                return canPerformResponderAction(Selector(("redo:")), sender: menuItem)
            case .cut:
                return canPerformResponderAction(#selector(NSText.cut(_:)), sender: menuItem)
            case .copy:
                return canPerformResponderAction(#selector(NSText.copy(_:)), sender: menuItem)
            case .paste:
                return canPerformResponderAction(#selector(NSText.paste(_:)), sender: menuItem)
            case .selectAll:
                return canPerformResponderAction(#selector(NSText.selectAll(_:)), sender: menuItem)
            case .find, .findNext, .findPrevious, .hideFind:
                return desktopApplication.hasFocusedPane
            case .refreshSelectedWorkspace:
                return desktopApplication.selectedWorkspaceSupportsRepositoryFeatures
            case .refreshAllRepositories:
                return desktopApplication.hasRepositoryWorkspaces
            case .newTab:
                return desktopApplication.hasSelectedWorkspace
            case .closeTab:
                return desktopApplication.canCloseFocusedPaneOrTab
            case .nextTab, .previousTab:
                return desktopApplication.selectedWorkspaceTabCount > 1
            case .selectTabByNumber:
                return menuItem.tag >= 1 && menuItem.tag <= desktopApplication.selectedWorkspaceTabCount
            case .focusPaneLeft,
                 .focusPaneRight,
                 .focusPaneUp,
                 .focusPaneDown,
                 .splitRight,
                 .splitDown,
                 .duplicatePane,
                 .togglePaneZoom,
                 .closePane:
                return desktopApplication.hasFocusedPane
            case .minimizeWindow, .closeWindow, .enterFullScreen:
                return NSApp.keyWindow != nil
            }
        default:
            return true
        }
    }

    private func shortcutAction(for menuItem: NSMenuItem) -> LineyShortcutAction? {
        guard let rawValue = menuItem.representedObject as? String else { return nil }
        return LineyShortcutAction(rawValue: rawValue)
    }

    @MainActor
    private func performShortcutAction(_ shortcutAction: LineyShortcutAction, tabNumber: Int) {
        switch shortcutAction {
        case .hideApp:
            NSApp.hide(nil)

        case .hideOtherApps:
            NSApp.hideOtherApplications(nil)

        case .quitApp:
            NSApp.terminate(nil)

        case .newWindow:
            desktopApplication?.createNewWindow()

        case .openSettings:
            desktopApplication?.presentSettings()

        case .undo:
            dispatchResponderAction(Selector(("undo:")), sender: nil)

        case .redo:
            dispatchResponderAction(Selector(("redo:")), sender: nil)

        case .cut:
            dispatchResponderAction(#selector(NSText.cut(_:)), sender: nil)

        case .copy:
            dispatchResponderAction(#selector(NSText.copy(_:)), sender: nil)

        case .paste:
            dispatchResponderAction(#selector(NSText.paste(_:)), sender: nil)

        case .selectAll:
            dispatchResponderAction(#selector(NSText.selectAll(_:)), sender: nil)

        case .find:
            desktopApplication?.findInFocusedPane()

        case .findNext:
            desktopApplication?.findNextInFocusedPane()

        case .findPrevious:
            desktopApplication?.findPreviousInFocusedPane()

        case .hideFind:
            desktopApplication?.hideFindInFocusedPane()

        case .toggleCommandPalette:
            desktopApplication?.toggleCommandPalette()

        case .toggleSidebar:
            NSApp.keyWindow?.firstResponder?.tryToPerform(
                #selector(NSSplitViewController.toggleSidebar(_:)),
                with: nil
            )

        case .toggleOverview:
            desktopApplication?.toggleOverview()

        case .openDiff:
            desktopApplication?.openDiffWindow()

        case .openHistory:
            desktopApplication?.openHistoryWindow()

        case .refreshSelectedWorkspace:
            desktopApplication?.refreshSelectedWorkspace()

        case .refreshAllRepositories:
            desktopApplication?.refreshAllRepositories()

        case .newTab:
            desktopApplication?.createTabInSelectedWorkspace()

        case .closeTab:
            desktopApplication?.closeFocusedPaneOrTab()

        case .nextTab:
            desktopApplication?.selectNextTab()

        case .previousTab:
            desktopApplication?.selectPreviousTab()

        case .selectTabByNumber:
            desktopApplication?.selectTab(number: tabNumber)

        case .focusPaneLeft:
            desktopApplication?.focusFocusedPane(in: .left)

        case .focusPaneRight:
            desktopApplication?.focusFocusedPane(in: .right)

        case .focusPaneUp:
            desktopApplication?.focusFocusedPane(in: .up)

        case .focusPaneDown:
            desktopApplication?.focusFocusedPane(in: .down)

        case .splitRight:
            desktopApplication?.splitFocusedPane(axis: .vertical)

        case .splitDown:
            desktopApplication?.splitFocusedPane(axis: .horizontal)

        case .duplicatePane:
            desktopApplication?.duplicateFocusedPane()

        case .togglePaneZoom:
            desktopApplication?.toggleFocusedPaneZoom()

        case .closePane:
            desktopApplication?.closeFocusedPane()

        case .minimizeWindow:
            NSApp.keyWindow?.performMiniaturize(nil)

        case .closeWindow:
            NSApp.keyWindow?.performClose(nil)

        case .enterFullScreen:
            NSApp.keyWindow?.toggleFullScreen(nil)
        }
    }

    @MainActor
    private func applicationName() -> String {
        if let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !displayName.isEmpty {
            return displayName
        }
        if let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !bundleName.isEmpty {
            return bundleName
        }
        return "Liney"
    }

    @MainActor
    private func refreshMainMenu() {
        applicationMenuController.installMainMenu(
            appName: applicationName(),
            target: self,
            settings: desktopApplication?.currentAppSettings ?? AppSettings()
        )
    }

    @MainActor
    private func formattedApplicationVersion() -> String {
        let shortVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let buildVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch (shortVersion?.isEmpty == false ? shortVersion : nil, buildVersion?.isEmpty == false ? buildVersion : nil) {
        case let (shortVersion?, buildVersion?) where shortVersion != buildVersion:
            return lineyLocalizedAppFormat("app.about.version.versionBuildFormat", shortVersion, buildVersion)
        case let (shortVersion?, _):
            return lineyLocalizedAppFormat("app.about.version.versionOnlyFormat", shortVersion)
        case let (_, buildVersion?):
            return lineyLocalizedAppFormat("app.about.version.buildOnlyFormat", buildVersion)
        default:
            return lineyLocalizedAppString("app.about.version.default")
        }
    }

    private func applicationReleaseVersion() -> String {
        let shortVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let shortVersion, !shortVersion.isEmpty {
            return shortVersion
        }

        let buildVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let buildVersion, !buildVersion.isEmpty {
            return buildVersion
        }

        return "0x00"
    }

    @MainActor
    private func aboutCredits() -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.paragraphSpacing = 6

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .paragraphStyle: paragraphStyle,
        ]
        let linkAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .paragraphStyle: paragraphStyle,
            .link: websiteURL,
        ]

        let credits = NSMutableAttributedString(
            string: "\(lineyLocalizedAppString("app.about.description"))\n\n",
            attributes: baseAttributes
        )
        credits.append(
            NSAttributedString(
                string: "\(lineyLocalizedAppFormat("app.about.websiteFormat", websiteURL.absoluteString))\n",
                attributes: linkAttributes.merging([.link: websiteURL]) { _, newValue in newValue }
            )
        )
        credits.append(
            NSAttributedString(
                string: lineyLocalizedAppFormat("app.about.githubFormat", repositoryURL.absoluteString),
                attributes: linkAttributes.merging([.link: repositoryURL]) { _, newValue in newValue }
            )
        )
        return credits
    }
}

func lineyIsRunningTests(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
    environment["XCTestConfigurationFilePath"] != nil
}

func lineyShouldTerminateAfterLastWindowClosed(
    hotKeyWindowEnabled: Bool,
    isRunningTests: Bool = false
) -> Bool {
    !hotKeyWindowEnabled && !isRunningTests
}

func lineyShouldReopenMainWindow(hasVisibleWindows: Bool) -> Bool {
    !hasVisibleWindows
}

func lineyShouldConfirmTermination(
    confirmQuitWhenCommandsRunning: Bool,
    needsConfirmQuit: Bool
) -> Bool {
    confirmQuitWhenCommandsRunning && needsConfirmQuit
}

func lineyQuitConfirmationCopy(quitConfirmationSessionCount: Int) -> (title: String, message: String) {
    let count = max(quitConfirmationSessionCount, 0)
    let subject = count == 1
        ? String(
            format: LocalizationManager.shared.string("quitConfirmation.subjectSingularFormat"),
            locale: Locale.current,
            count
        )
        : String(
            format: LocalizationManager.shared.string("quitConfirmation.subjectPluralFormat"),
            locale: Locale.current,
            count
        )
    let impact = count == 1
        ? LocalizationManager.shared.string("quitConfirmation.impactSingular")
        : LocalizationManager.shared.string("quitConfirmation.impactPlural")
    return (
        title: LocalizationManager.shared.string("quitConfirmation.title"),
        message: "\(subject) \(impact) \(LocalizationManager.shared.string("quitConfirmation.settingsHint"))"
    )
}
