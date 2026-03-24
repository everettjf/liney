//
//  AppDelegate.swift
//  Liney
//
//  Author: everettjf
//

import Cocoa
import Sentry

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let websiteURL = URL(string: "https://liney.dev")!
    private let repositoryURL = URL(string: "https://github.com/everettjf/liney")!
    private let quitConfirmationSuppressionInterval: TimeInterval = 0.5

    @MainActor private var desktopApplication: LineyDesktopApplication?
    @MainActor private let applicationMenuController = ApplicationMenuController()
    private var appSettingsObserver: NSObjectProtocol?
    private var isPresentingQuitConfirmation = false
    private var suppressQuitConfirmationUntil: Date?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
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
                }
            }
            desktopApplication.launch()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.applicationMenuController.installMainMenu(
                    appName: self.applicationName(),
                    target: self,
                    settings: AppSettings()
                )
            }
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        if let appSettingsObserver {
            NotificationCenter.default.removeObserver(appSettingsObserver)
            self.appSettingsObserver = nil
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
                hotKeyWindowEnabled: desktopApplication?.isHotKeyWindowEnabled ?? false
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
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Cancel")
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
            guard lineyShouldReopenMainWindow(hasVisibleWindows: flag) else { return false }
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
            switch shortcutAction {
            case .newWindow:
                desktopApplication?.createNewWindow()

            case .openSettings:
                desktopApplication?.presentSettings()

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

            case .refreshSelectedWorkspace:
                desktopApplication?.refreshSelectedWorkspace()

            case .refreshAllRepositories:
                desktopApplication?.refreshAllRepositories()

            case .newTab:
                desktopApplication?.createTabInSelectedWorkspace()

            case .closeTab:
                desktopApplication?.closeSelectedTab()

            case .nextTab:
                desktopApplication?.selectNextTab()

            case .previousTab:
                desktopApplication?.selectPreviousTab()

            case .selectTabByNumber:
                desktopApplication?.selectTab(number: sender.tag)

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

            case .closeWindow:
                NSApp.keyWindow?.performClose(nil)

            case .enterFullScreen:
                NSApp.keyWindow?.toggleFullScreen(nil)
            }
        }
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
            case .newWindow,
                 .openSettings,
                 .toggleCommandPalette,
                 .toggleSidebar,
                 .toggleOverview,
                 .openDiff:
                return true
            case .refreshSelectedWorkspace:
                return desktopApplication.selectedWorkspaceSupportsRepositoryFeatures
            case .refreshAllRepositories:
                return desktopApplication.hasRepositoryWorkspaces
            case .newTab:
                return desktopApplication.hasSelectedWorkspace
            case .closeTab:
                return desktopApplication.canCloseSelectedTab
            case .nextTab, .previousTab:
                return desktopApplication.selectedWorkspaceTabCount > 1
            case .selectTabByNumber:
                return menuItem.tag >= 1 && menuItem.tag <= desktopApplication.selectedWorkspaceTabCount
            case .splitRight,
                 .splitDown,
                 .duplicatePane,
                 .togglePaneZoom,
                 .closePane:
                return desktopApplication.hasFocusedPane
            case .closeWindow, .enterFullScreen:
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
    private func formattedApplicationVersion() -> String {
        let shortVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let buildVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch (shortVersion?.isEmpty == false ? shortVersion : nil, buildVersion?.isEmpty == false ? buildVersion : nil) {
        case let (shortVersion?, buildVersion?) where shortVersion != buildVersion:
            return "Version \(shortVersion) (\(buildVersion))"
        case let (shortVersion?, _):
            return "Version \(shortVersion)"
        case let (_, buildVersion?):
            return "Build \(buildVersion)"
        default:
            return "Version 1.0.0"
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
            string: "Native macOS terminal workspace.\n\n",
            attributes: baseAttributes
        )
        credits.append(
            NSAttributedString(
                string: "Website: \(websiteURL.absoluteString)\n",
                attributes: linkAttributes.merging([.link: websiteURL]) { _, newValue in newValue }
            )
        )
        credits.append(
            NSAttributedString(
                string: "GitHub: \(repositoryURL.absoluteString)",
                attributes: linkAttributes.merging([.link: repositoryURL]) { _, newValue in newValue }
            )
        )
        return credits
    }
}

func lineyShouldTerminateAfterLastWindowClosed(hotKeyWindowEnabled: Bool) -> Bool {
    !hotKeyWindowEnabled
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
        ? "1 terminal session still has a running command."
        : "\(count) terminal sessions still have running commands."
    let impact = count == 1 ? "Quitting now will stop it." : "Quitting now will stop them."
    return (
        title: "Quit Liney?",
        message: "\(subject) \(impact) You can turn this confirmation off in Settings > General."
    )
}
