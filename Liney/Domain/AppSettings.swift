//
//  AppSettings.swift
//  Liney
//
//  Author: everettjf
//

import AppKit
import Carbon
import Foundation

nonisolated enum SidebarIconFillStyle: String, Codable, Hashable, CaseIterable, Identifiable {
    case solid
    case gradient

    var id: String { rawValue }

    var title: String {
        switch self {
        case .solid:
            return "Solid"
        case .gradient:
            return "Gradient"
        }
    }
}

nonisolated enum SidebarIconPalette: String, Codable, Hashable, CaseIterable, Identifiable {
    case blue
    case cyan
    case aqua
    case ice
    case sky
    case teal
    case turquoise
    case mint
    case green
    case forest
    case lime
    case olive
    case gold
    case sand
    case bronze
    case amber
    case orange
    case copper
    case rust
    case coral
    case peach
    case brick
    case crimson
    case ruby
    case berry
    case rose
    case magenta
    case orchid
    case indigo
    case navy
    case steel
    case violet
    case iris
    case lavender
    case plum
    case slate
    case smoke
    case charcoal
    case graphite
    case mocha

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blue:
            return "Blue"
        case .cyan:
            return "Cyan"
        case .aqua:
            return "Aqua"
        case .ice:
            return "Ice"
        case .sky:
            return "Sky"
        case .teal:
            return "Teal"
        case .turquoise:
            return "Turquoise"
        case .mint:
            return "Mint"
        case .green:
            return "Green"
        case .forest:
            return "Forest"
        case .lime:
            return "Lime"
        case .olive:
            return "Olive"
        case .gold:
            return "Gold"
        case .sand:
            return "Sand"
        case .bronze:
            return "Bronze"
        case .amber:
            return "Amber"
        case .orange:
            return "Orange"
        case .copper:
            return "Copper"
        case .rust:
            return "Rust"
        case .coral:
            return "Coral"
        case .peach:
            return "Peach"
        case .brick:
            return "Brick"
        case .crimson:
            return "Crimson"
        case .ruby:
            return "Ruby"
        case .berry:
            return "Berry"
        case .rose:
            return "Rose"
        case .magenta:
            return "Magenta"
        case .orchid:
            return "Orchid"
        case .indigo:
            return "Indigo"
        case .navy:
            return "Navy"
        case .steel:
            return "Steel"
        case .violet:
            return "Violet"
        case .iris:
            return "Iris"
        case .lavender:
            return "Lavender"
        case .plum:
            return "Plum"
        case .slate:
            return "Slate"
        case .smoke:
            return "Smoke"
        case .charcoal:
            return "Charcoal"
        case .graphite:
            return "Graphite"
        case .mocha:
            return "Mocha"
        }
    }
}

nonisolated struct SidebarItemIcon: Codable, Hashable {
    var symbolName: String
    var palette: SidebarIconPalette
    var fillStyle: SidebarIconFillStyle

    init(
        symbolName: String,
        palette: SidebarIconPalette,
        fillStyle: SidebarIconFillStyle = .gradient
    ) {
        self.symbolName = symbolName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "square.grid.2x2.fill"
        self.palette = palette
        self.fillStyle = fillStyle
    }
}

extension SidebarItemIcon {
    nonisolated static let repositoryDefault = SidebarItemIcon(
        symbolName: "arrow.triangle.branch",
        palette: .blue,
        fillStyle: .gradient
    )

    nonisolated static let localTerminalDefault = SidebarItemIcon(
        symbolName: "terminal.fill",
        palette: .teal,
        fillStyle: .solid
    )

    nonisolated static let worktreeDefault = SidebarItemIcon(
        symbolName: "circle.fill",
        palette: .mint,
        fillStyle: .solid
    )
}

nonisolated enum ExternalEditor: String, Codable, Hashable, CaseIterable, Identifiable {
    case cursor
    case zed
    case visualStudioCode
    case visualStudioCodeInsiders
    case windsurf
    case fleet
    case xcode
    case nova
    case sublimeText

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cursor:
            return "Cursor"
        case .zed:
            return "Zed"
        case .visualStudioCode:
            return "VS Code"
        case .visualStudioCodeInsiders:
            return "VS Code Insiders"
        case .windsurf:
            return "Windsurf"
        case .fleet:
            return "Fleet"
        case .xcode:
            return "Xcode"
        case .nova:
            return "Nova"
        case .sublimeText:
            return "Sublime Text"
        }
    }
}

struct AppSettings: Codable, Hashable {
    var autoRefreshEnabled: Bool
    var autoRefreshIntervalSeconds: Int
    var autoClosePaneOnProcessExit: Bool
    var confirmQuitWhenCommandsRunning: Bool
    var hotKeyWindowEnabled: Bool
    var hotKeyWindowShortcut: StoredShortcut
    var fileWatcherEnabled: Bool
    var githubIntegrationEnabled: Bool
    var autoCheckForUpdates: Bool
    var autoDownloadUpdates: Bool
    var systemNotificationsEnabled: Bool
    var showArchivedWorkspaces: Bool
    var terminalFontSize: Double?
    var sidebarShowsSecondaryLabels: Bool
    var sidebarShowsWorkspaceBadges: Bool
    var sidebarShowsWorktreeBadges: Bool
    var defaultRepositoryIcon: SidebarItemIcon
    var defaultLocalTerminalIcon: SidebarItemIcon
    var defaultWorktreeIcon: SidebarItemIcon
    var preferredExternalEditor: ExternalEditor
    var quickCommandPresets: [QuickCommandPreset]
    var quickCommandRecentIDs: [String]
    var releaseChannel: ReleaseChannel
    var commandPaletteRecents: [String: TimeInterval]
    var keyboardShortcutOverrides: [String: KeyboardShortcutOverride]

    init(
        autoRefreshEnabled: Bool = true,
        autoRefreshIntervalSeconds: Int = 30,
        autoClosePaneOnProcessExit: Bool = true,
        confirmQuitWhenCommandsRunning: Bool = true,
        hotKeyWindowEnabled: Bool = false,
        hotKeyWindowShortcut: StoredShortcut = StoredShortcut(key: " ", command: true, shift: true, option: false, control: false),
        fileWatcherEnabled: Bool = true,
        githubIntegrationEnabled: Bool = true,
        autoCheckForUpdates: Bool = true,
        autoDownloadUpdates: Bool = false,
        systemNotificationsEnabled: Bool = true,
        showArchivedWorkspaces: Bool = false,
        terminalFontSize: Double? = nil,
        sidebarShowsSecondaryLabels: Bool = true,
        sidebarShowsWorkspaceBadges: Bool = true,
        sidebarShowsWorktreeBadges: Bool = true,
        defaultRepositoryIcon: SidebarItemIcon = .repositoryDefault,
        defaultLocalTerminalIcon: SidebarItemIcon = .localTerminalDefault,
        defaultWorktreeIcon: SidebarItemIcon = .worktreeDefault,
        preferredExternalEditor: ExternalEditor = .cursor,
        quickCommandPresets: [QuickCommandPreset] = QuickCommandCatalog.defaultCommands,
        quickCommandRecentIDs: [String] = [],
        releaseChannel: ReleaseChannel = .stable,
        commandPaletteRecents: [String: TimeInterval] = [:],
        keyboardShortcutOverrides: [String: KeyboardShortcutOverride] = [:]
    ) {
        self.autoRefreshEnabled = autoRefreshEnabled
        self.autoRefreshIntervalSeconds = max(10, autoRefreshIntervalSeconds)
        self.autoClosePaneOnProcessExit = autoClosePaneOnProcessExit
        self.confirmQuitWhenCommandsRunning = confirmQuitWhenCommandsRunning
        self.hotKeyWindowEnabled = hotKeyWindowEnabled
        self.hotKeyWindowShortcut = hotKeyWindowShortcut
        self.fileWatcherEnabled = fileWatcherEnabled
        self.githubIntegrationEnabled = githubIntegrationEnabled
        self.autoCheckForUpdates = autoCheckForUpdates
        self.autoDownloadUpdates = autoDownloadUpdates
        self.systemNotificationsEnabled = systemNotificationsEnabled
        self.showArchivedWorkspaces = showArchivedWorkspaces
        self.terminalFontSize = terminalFontSize.map { min(max($0, 8), 32) }
        self.sidebarShowsSecondaryLabels = sidebarShowsSecondaryLabels
        self.sidebarShowsWorkspaceBadges = sidebarShowsWorkspaceBadges
        self.sidebarShowsWorktreeBadges = sidebarShowsWorktreeBadges
        self.defaultRepositoryIcon = defaultRepositoryIcon
        self.defaultLocalTerminalIcon = defaultLocalTerminalIcon
        self.defaultWorktreeIcon = defaultWorktreeIcon
        self.preferredExternalEditor = preferredExternalEditor
        self.quickCommandPresets = QuickCommandCatalog.normalizedCommands(quickCommandPresets)
        self.quickCommandRecentIDs = QuickCommandCatalog.normalizedRecentCommandIDs(
            quickCommandRecentIDs,
            availableCommands: self.quickCommandPresets
        )
        self.releaseChannel = releaseChannel
        self.commandPaletteRecents = commandPaletteRecents
        self.keyboardShortcutOverrides = LineyKeyboardShortcuts.normalizedOverrides(keyboardShortcutOverrides)
    }
}

extension AppSettings {
    private enum CodingKeys: String, CodingKey {
        case autoRefreshEnabled
        case autoRefreshIntervalSeconds
        case autoClosePaneOnProcessExit
        case confirmQuitWhenCommandsRunning
        case hotKeyWindowEnabled
        case hotKeyWindowShortcut
        case fileWatcherEnabled
        case githubIntegrationEnabled
        case autoCheckForUpdates
        case autoDownloadUpdates
        case systemNotificationsEnabled
        case showArchivedWorkspaces
        case terminalFontSize
        case sidebarShowsSecondaryLabels
        case sidebarShowsWorkspaceBadges
        case sidebarShowsWorktreeBadges
        case defaultRepositoryIcon
        case defaultLocalTerminalIcon
        case defaultWorktreeIcon
        case preferredExternalEditor
        case quickCommandPresets
        case quickCommandRecentIDs
        case releaseChannel
        case commandPaletteRecents
        case keyboardShortcutOverrides
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let preferredExternalEditor: ExternalEditor
        if let rawValue = try container.decodeIfPresent(String.self, forKey: .preferredExternalEditor),
           let decoded = ExternalEditor(rawValue: rawValue) {
            preferredExternalEditor = decoded
        } else {
            preferredExternalEditor = .cursor
        }
        self.init(
            autoRefreshEnabled: try container.decodeIfPresent(Bool.self, forKey: .autoRefreshEnabled) ?? true,
            autoRefreshIntervalSeconds: try container.decodeIfPresent(Int.self, forKey: .autoRefreshIntervalSeconds) ?? 30,
            autoClosePaneOnProcessExit: try container.decodeIfPresent(Bool.self, forKey: .autoClosePaneOnProcessExit) ?? true,
            confirmQuitWhenCommandsRunning: try container.decodeIfPresent(Bool.self, forKey: .confirmQuitWhenCommandsRunning) ?? true,
            hotKeyWindowEnabled: try container.decodeIfPresent(Bool.self, forKey: .hotKeyWindowEnabled) ?? false,
            hotKeyWindowShortcut: try container.decodeIfPresent(StoredShortcut.self, forKey: .hotKeyWindowShortcut)
                ?? StoredShortcut(key: " ", command: true, shift: true, option: false, control: false),
            fileWatcherEnabled: try container.decodeIfPresent(Bool.self, forKey: .fileWatcherEnabled) ?? true,
            githubIntegrationEnabled: try container.decodeIfPresent(Bool.self, forKey: .githubIntegrationEnabled) ?? true,
            autoCheckForUpdates: try container.decodeIfPresent(Bool.self, forKey: .autoCheckForUpdates) ?? true,
            autoDownloadUpdates: try container.decodeIfPresent(Bool.self, forKey: .autoDownloadUpdates) ?? false,
            systemNotificationsEnabled: try container.decodeIfPresent(Bool.self, forKey: .systemNotificationsEnabled) ?? true,
            showArchivedWorkspaces: try container.decodeIfPresent(Bool.self, forKey: .showArchivedWorkspaces) ?? false,
            terminalFontSize: try container.decodeIfPresent(Double.self, forKey: .terminalFontSize),
            sidebarShowsSecondaryLabels: try container.decodeIfPresent(Bool.self, forKey: .sidebarShowsSecondaryLabels) ?? true,
            sidebarShowsWorkspaceBadges: try container.decodeIfPresent(Bool.self, forKey: .sidebarShowsWorkspaceBadges) ?? true,
            sidebarShowsWorktreeBadges: try container.decodeIfPresent(Bool.self, forKey: .sidebarShowsWorktreeBadges) ?? true,
            defaultRepositoryIcon: try container.decodeIfPresent(SidebarItemIcon.self, forKey: .defaultRepositoryIcon) ?? .repositoryDefault,
            defaultLocalTerminalIcon: try container.decodeIfPresent(SidebarItemIcon.self, forKey: .defaultLocalTerminalIcon) ?? .localTerminalDefault,
            defaultWorktreeIcon: try container.decodeIfPresent(SidebarItemIcon.self, forKey: .defaultWorktreeIcon) ?? .worktreeDefault,
            preferredExternalEditor: preferredExternalEditor,
            quickCommandPresets: try container.decodeIfPresent([QuickCommandPreset].self, forKey: .quickCommandPresets) ?? QuickCommandCatalog.defaultCommands,
            quickCommandRecentIDs: try container.decodeIfPresent([String].self, forKey: .quickCommandRecentIDs) ?? [],
            releaseChannel: try container.decodeIfPresent(ReleaseChannel.self, forKey: .releaseChannel) ?? .stable,
            commandPaletteRecents: try container.decodeIfPresent([String: TimeInterval].self, forKey: .commandPaletteRecents) ?? [:],
            keyboardShortcutOverrides: try container.decodeIfPresent([String: KeyboardShortcutOverride].self, forKey: .keyboardShortcutOverrides) ?? [:]
        )
    }
}

struct StoredShortcut: Codable, Hashable {
    var key: String
    var command: Bool
    var shift: Bool
    var option: Bool
    var control: Bool

    var displayString: String {
        modifierDisplayString + keyDisplayString
    }

    var modifierDisplayString: String {
        var parts: [String] = []
        if control { parts.append("⌃") }
        if option { parts.append("⌥") }
        if shift { parts.append("⇧") }
        if command { parts.append("⌘") }
        return parts.joined()
    }

    var keyDisplayString: String {
        switch key {
        case "\t":
            return "TAB"
        case "\r":
            return "↩"
        case " ":
            return "SPACE"
        default:
            return key.uppercased()
        }
    }

    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if command { flags.insert(.command) }
        if shift { flags.insert(.shift) }
        if option { flags.insert(.option) }
        if control { flags.insert(.control) }
        return flags
    }

    var menuItemKeyEquivalent: String? {
        switch key {
        case "←":
            guard let scalar = UnicodeScalar(NSLeftArrowFunctionKey) else { return nil }
            return String(Character(scalar))
        case "→":
            guard let scalar = UnicodeScalar(NSRightArrowFunctionKey) else { return nil }
            return String(Character(scalar))
        case "↑":
            guard let scalar = UnicodeScalar(NSUpArrowFunctionKey) else { return nil }
            return String(Character(scalar))
        case "↓":
            guard let scalar = UnicodeScalar(NSDownArrowFunctionKey) else { return nil }
            return String(Character(scalar))
        case "\t":
            return "\t"
        case "\r":
            return "\r"
        case " ":
            return " "
        default:
            let lowered = key.lowercased()
            guard lowered.count == 1 else { return nil }
            return lowered
        }
    }

    func withKey(_ key: String) -> StoredShortcut {
        StoredShortcut(
            key: key,
            command: command,
            shift: shift,
            option: option,
            control: control
        )
    }

    static func from(event: NSEvent) -> StoredShortcut? {
        guard let key = storedKey(from: event) else { return nil }

        let flags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function])

        let shortcut = StoredShortcut(
            key: key,
            command: flags.contains(.command),
            shift: flags.contains(.shift),
            option: flags.contains(.option),
            control: flags.contains(.control)
        )

        guard shortcut.command || shortcut.shift || shortcut.option || shortcut.control else {
            return nil
        }
        return shortcut
    }

    private static func storedKey(from event: NSEvent) -> String? {
        switch event.keyCode {
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 48: return "\t"
        case 36, 76: return "\r"
        case 49: return " "
        case 33: return "["
        case 30: return "]"
        case 27: return "-"
        case 24: return "="
        case 43: return ","
        case 47: return "."
        case 44: return "/"
        case 41: return ";"
        case 39: return "'"
        case 50: return "`"
        case 42: return "\\"
        default:
            break
        }

        guard let chars = event.charactersIgnoringModifiers?.lowercased(),
              let char = chars.first else {
            return nil
        }

        if char.isLetter || char.isNumber {
            return String(char)
        }
        return nil
    }
}

extension StoredShortcut {
    private static let keyCodeByStoredKey: [String: UInt32] = [
        "a": UInt32(kVK_ANSI_A),
        "b": UInt32(kVK_ANSI_B),
        "c": UInt32(kVK_ANSI_C),
        "d": UInt32(kVK_ANSI_D),
        "e": UInt32(kVK_ANSI_E),
        "f": UInt32(kVK_ANSI_F),
        "g": UInt32(kVK_ANSI_G),
        "h": UInt32(kVK_ANSI_H),
        "i": UInt32(kVK_ANSI_I),
        "j": UInt32(kVK_ANSI_J),
        "k": UInt32(kVK_ANSI_K),
        "l": UInt32(kVK_ANSI_L),
        "m": UInt32(kVK_ANSI_M),
        "n": UInt32(kVK_ANSI_N),
        "o": UInt32(kVK_ANSI_O),
        "p": UInt32(kVK_ANSI_P),
        "q": UInt32(kVK_ANSI_Q),
        "r": UInt32(kVK_ANSI_R),
        "s": UInt32(kVK_ANSI_S),
        "t": UInt32(kVK_ANSI_T),
        "u": UInt32(kVK_ANSI_U),
        "v": UInt32(kVK_ANSI_V),
        "w": UInt32(kVK_ANSI_W),
        "x": UInt32(kVK_ANSI_X),
        "y": UInt32(kVK_ANSI_Y),
        "z": UInt32(kVK_ANSI_Z),
        "0": UInt32(kVK_ANSI_0),
        "1": UInt32(kVK_ANSI_1),
        "2": UInt32(kVK_ANSI_2),
        "3": UInt32(kVK_ANSI_3),
        "4": UInt32(kVK_ANSI_4),
        "5": UInt32(kVK_ANSI_5),
        "6": UInt32(kVK_ANSI_6),
        "7": UInt32(kVK_ANSI_7),
        "8": UInt32(kVK_ANSI_8),
        "9": UInt32(kVK_ANSI_9),
        " ": UInt32(kVK_Space),
        "\t": UInt32(kVK_Tab),
        "\r": UInt32(kVK_Return),
        "[": UInt32(kVK_ANSI_LeftBracket),
        "]": UInt32(kVK_ANSI_RightBracket),
        "-": UInt32(kVK_ANSI_Minus),
        "=": UInt32(kVK_ANSI_Equal),
        ",": UInt32(kVK_ANSI_Comma),
        ".": UInt32(kVK_ANSI_Period),
        "/": UInt32(kVK_ANSI_Slash),
        ";": UInt32(kVK_ANSI_Semicolon),
        "'": UInt32(kVK_ANSI_Quote),
        "`": UInt32(kVK_ANSI_Grave),
        "\\": UInt32(kVK_ANSI_Backslash),
        "←": UInt32(kVK_LeftArrow),
        "→": UInt32(kVK_RightArrow),
        "↑": UInt32(kVK_UpArrow),
        "↓": UInt32(kVK_DownArrow),
    ]

    var carbonKeyCode: UInt32? {
        Self.keyCodeByStoredKey[key.lowercased()]
    }

    var carbonModifierFlags: UInt32 {
        var flags: UInt32 = 0
        if command { flags |= UInt32(cmdKey) }
        if shift { flags |= UInt32(shiftKey) }
        if option { flags |= UInt32(optionKey) }
        if control { flags |= UInt32(controlKey) }
        return flags
    }
}

struct KeyboardShortcutOverride: Codable, Hashable {
    var shortcut: StoredShortcut?
}

enum LineyShortcutCategory: String, CaseIterable, Hashable, Identifiable {
    case general
    case workspace
    case tabs
    case panes
    case window

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .workspace:
            return "Workspace"
        case .tabs:
            return "Tabs"
        case .panes:
            return "Panes"
        case .window:
            return "Window"
        }
    }
}

enum LineyShortcutAction: String, CaseIterable, Hashable, Identifiable {
    case newWindow
    case openSettings
    case toggleCommandPalette
    case toggleSidebar
    case toggleOverview
    case openDiff
    case refreshSelectedWorkspace
    case refreshAllRepositories
    case newTab
    case closeTab
    case nextTab
    case previousTab
    case selectTabByNumber
    case focusPaneLeft
    case focusPaneRight
    case focusPaneUp
    case focusPaneDown
    case splitRight
    case splitDown
    case duplicatePane
    case togglePaneZoom
    case closePane
    case closeWindow
    case enterFullScreen

    var id: String { rawValue }

    var category: LineyShortcutCategory {
        switch self {
        case .openSettings,
             .toggleCommandPalette,
             .toggleSidebar,
             .toggleOverview,
             .openDiff:
            return .general
        case .refreshSelectedWorkspace,
             .refreshAllRepositories:
            return .workspace
        case .newTab,
             .closeTab,
             .nextTab,
             .previousTab,
             .selectTabByNumber:
            return .tabs
        case .focusPaneLeft,
             .focusPaneRight,
             .focusPaneUp,
             .focusPaneDown,
             .splitRight,
             .splitDown,
             .duplicatePane,
             .togglePaneZoom,
             .closePane:
            return .panes
        case .newWindow,
             .closeWindow,
             .enterFullScreen:
            return .window
        }
    }

    var title: String {
        switch self {
        case .newWindow:
            return "New Window"
        case .openSettings:
            return "Settings"
        case .toggleCommandPalette:
            return "Command Palette"
        case .toggleSidebar:
            return "Toggle Sidebar"
        case .toggleOverview:
            return "Toggle Overview"
        case .openDiff:
            return "Open Diff"
        case .refreshSelectedWorkspace:
            return "Refresh Selected Workspace"
        case .refreshAllRepositories:
            return "Refresh All Repositories"
        case .newTab:
            return "New Tab"
        case .closeTab:
            return "Close Tab"
        case .nextTab:
            return "Next Tab"
        case .previousTab:
            return "Previous Tab"
        case .selectTabByNumber:
            return "Select Tab 1…9"
        case .focusPaneLeft:
            return "Focus Pane Left"
        case .focusPaneRight:
            return "Focus Pane Right"
        case .focusPaneUp:
            return "Focus Pane Up"
        case .focusPaneDown:
            return "Focus Pane Down"
        case .splitRight:
            return "Split Right"
        case .splitDown:
            return "Split Down"
        case .duplicatePane:
            return "Duplicate Pane"
        case .togglePaneZoom:
            return "Toggle Pane Zoom"
        case .closePane:
            return "Close Pane"
        case .closeWindow:
            return "Close Window"
        case .enterFullScreen:
            return "Enter Full Screen"
        }
    }

    var subtitle: String {
        switch self {
        case .newWindow:
            return "Open another Liney window with its own workspace selection."
        case .openSettings:
            return "Open the Liney settings window."
        case .toggleCommandPalette:
            return "Search and run workspace actions."
        case .toggleSidebar:
            return "Show or hide the repository sidebar."
        case .toggleOverview:
            return "Open or close the workspace overview."
        case .openDiff:
            return "Open the current workspace diff window."
        case .refreshSelectedWorkspace:
            return "Reload git status for the selected workspace."
        case .refreshAllRepositories:
            return "Refresh every repository in the sidebar."
        case .newTab:
            return "Create a new tab in the selected workspace."
        case .closeTab:
            return "Close the active tab without closing the app window."
        case .nextTab:
            return "Select the next tab in the current workspace."
        case .previousTab:
            return "Select the previous tab in the current workspace."
        case .selectTabByNumber:
            return "Jump directly to tabs 1 through 9."
        case .focusPaneLeft:
            return "Move focus to the pane on the left."
        case .focusPaneRight:
            return "Move focus to the pane on the right."
        case .focusPaneUp:
            return "Move focus to the pane above."
        case .focusPaneDown:
            return "Move focus to the pane below."
        case .splitRight:
            return "Split the focused pane to the right."
        case .splitDown:
            return "Split the focused pane downward."
        case .duplicatePane:
            return "Duplicate the focused pane."
        case .togglePaneZoom:
            return "Zoom or unzoom the focused pane."
        case .closePane:
            return "Close the focused pane."
        case .closeWindow:
            return "Close the current Liney window."
        case .enterFullScreen:
            return "Toggle macOS full screen for the current window."
        }
    }

    var defaultShortcut: StoredShortcut? {
        switch self {
        case .newWindow:
            return StoredShortcut(key: "n", command: true, shift: false, option: false, control: false)
        case .openSettings:
            return StoredShortcut(key: ",", command: true, shift: false, option: false, control: false)
        case .toggleCommandPalette:
            return StoredShortcut(key: "p", command: true, shift: false, option: false, control: false)
        case .toggleSidebar:
            return StoredShortcut(key: "b", command: true, shift: false, option: false, control: false)
        case .toggleOverview:
            return StoredShortcut(key: "o", command: true, shift: true, option: false, control: false)
        case .openDiff:
            return nil
        case .refreshSelectedWorkspace:
            return StoredShortcut(key: "r", command: true, shift: false, option: false, control: false)
        case .refreshAllRepositories:
            return StoredShortcut(key: "r", command: true, shift: true, option: false, control: false)
        case .newTab:
            return StoredShortcut(key: "t", command: true, shift: false, option: false, control: false)
        case .closeTab:
            return StoredShortcut(key: "w", command: true, shift: false, option: false, control: false)
        case .nextTab:
            return StoredShortcut(key: "]", command: true, shift: false, option: false, control: false)
        case .previousTab:
            return StoredShortcut(key: "[", command: true, shift: false, option: false, control: false)
        case .selectTabByNumber:
            return StoredShortcut(key: "1", command: true, shift: false, option: false, control: false)
        case .focusPaneLeft:
            return StoredShortcut(key: "←", command: true, shift: false, option: true, control: false)
        case .focusPaneRight:
            return StoredShortcut(key: "→", command: true, shift: false, option: true, control: false)
        case .focusPaneUp:
            return StoredShortcut(key: "↑", command: true, shift: false, option: true, control: false)
        case .focusPaneDown:
            return StoredShortcut(key: "↓", command: true, shift: false, option: true, control: false)
        case .splitRight:
            return StoredShortcut(key: "d", command: true, shift: false, option: false, control: false)
        case .splitDown:
            return StoredShortcut(key: "d", command: true, shift: true, option: false, control: false)
        case .duplicatePane:
            return nil
        case .togglePaneZoom:
            return nil
        case .closePane:
            return StoredShortcut(key: "w", command: true, shift: true, option: false, control: false)
        case .closeWindow:
            return StoredShortcut(key: "w", command: true, shift: false, option: false, control: true)
        case .enterFullScreen:
            return StoredShortcut(key: "f", command: true, shift: false, option: false, control: true)
        }
    }

    var usesNumberedDigitMatching: Bool {
        self == .selectTabByNumber
    }

    func normalizedRecordedShortcut(_ shortcut: StoredShortcut) -> StoredShortcut? {
        guard usesNumberedDigitMatching else { return shortcut }
        guard let digit = Int(shortcut.key), (1...9).contains(digit) else {
            return nil
        }
        return shortcut.withKey("1")
    }

    func displayedShortcutString(for shortcut: StoredShortcut) -> String {
        if usesNumberedDigitMatching {
            return shortcut.modifierDisplayString + "1…9"
        }
        return shortcut.displayString
    }
}

enum LineyKeyboardShortcutState: Equatable {
    case `default`
    case custom
    case disabled
}

enum LineyKeyboardShortcuts {
    private enum Candidate {
        case inheritDefault
        case custom(StoredShortcut)
        case disabled
    }

    static func effectiveShortcut(for action: LineyShortcutAction, in settings: AppSettings) -> StoredShortcut? {
        if let override = settings.keyboardShortcutOverrides[action.rawValue] {
            return override.shortcut
        }
        return action.defaultShortcut
    }

    static func state(for action: LineyShortcutAction, in settings: AppSettings) -> LineyKeyboardShortcutState {
        guard let override = settings.keyboardShortcutOverrides[action.rawValue] else {
            return .default
        }
        return override.shortcut == nil ? .disabled : .custom
    }

    static func displayString(for action: LineyShortcutAction, in settings: AppSettings) -> String {
        guard let shortcut = effectiveShortcut(for: action, in: settings) else {
            return "Not Set"
        }
        return action.displayedShortcutString(for: shortcut)
    }

    static func setShortcut(_ shortcut: StoredShortcut, for action: LineyShortcutAction, in settings: inout AppSettings) {
        guard let normalizedShortcut = action.normalizedRecordedShortcut(shortcut) else { return }

        for otherAction in LineyShortcutAction.allCases where otherAction != action {
            if effectiveShortcut(for: otherAction, in: settings) == normalizedShortcut {
                settings.keyboardShortcutOverrides[otherAction.rawValue] = KeyboardShortcutOverride(shortcut: nil)
            }
        }

        if normalizedShortcut == action.defaultShortcut {
            settings.keyboardShortcutOverrides.removeValue(forKey: action.rawValue)
        } else {
            settings.keyboardShortcutOverrides[action.rawValue] = KeyboardShortcutOverride(shortcut: normalizedShortcut)
        }

        settings.keyboardShortcutOverrides = normalizedOverrides(settings.keyboardShortcutOverrides)
    }

    static func disableShortcut(for action: LineyShortcutAction, in settings: inout AppSettings) {
        settings.keyboardShortcutOverrides[action.rawValue] = KeyboardShortcutOverride(shortcut: nil)
        settings.keyboardShortcutOverrides = normalizedOverrides(settings.keyboardShortcutOverrides)
    }

    static func resetShortcut(for action: LineyShortcutAction, in settings: inout AppSettings) {
        settings.keyboardShortcutOverrides.removeValue(forKey: action.rawValue)
        settings.keyboardShortcutOverrides = normalizedOverrides(settings.keyboardShortcutOverrides)
    }

    static func resetAll(in settings: inout AppSettings) {
        settings.keyboardShortcutOverrides = [:]
    }

    static func normalizedOverrides(_ overrides: [String: KeyboardShortcutOverride]) -> [String: KeyboardShortcutOverride] {
        var candidates: [LineyShortcutAction: Candidate] = [:]

        for action in LineyShortcutAction.allCases {
            guard let override = overrides[action.rawValue] else { continue }

            if let shortcut = override.shortcut {
                guard let normalizedShortcut = action.normalizedRecordedShortcut(shortcut) else { continue }
                if normalizedShortcut == action.defaultShortcut {
                    continue
                }
                candidates[action] = .custom(normalizedShortcut)
            } else {
                candidates[action] = .disabled
            }
        }

        var normalized: [String: KeyboardShortcutOverride] = [:]
        var seenShortcuts = Set<StoredShortcut>()

        for action in LineyShortcutAction.allCases {
            let candidate = candidates[action] ?? .inheritDefault

            let effectiveShortcut: StoredShortcut?
            switch candidate {
            case .inheritDefault:
                effectiveShortcut = action.defaultShortcut
            case .custom(let shortcut):
                effectiveShortcut = shortcut
            case .disabled:
                effectiveShortcut = nil
            }

            if let effectiveShortcut {
                if seenShortcuts.contains(effectiveShortcut) {
                    normalized[action.rawValue] = KeyboardShortcutOverride(shortcut: nil)
                    continue
                }
                seenShortcuts.insert(effectiveShortcut)

                if case .custom(let shortcut) = candidate {
                    normalized[action.rawValue] = KeyboardShortcutOverride(shortcut: shortcut)
                }
            } else if case .disabled = candidate {
                normalized[action.rawValue] = KeyboardShortcutOverride(shortcut: nil)
            }
        }

        return normalized
    }
}

struct LineyShortcutMatch: Equatable {
    var action: LineyShortcutAction
    var tabNumber: Int?
}

func lineyShortcutMatch(for event: NSEvent, in settings: AppSettings) -> LineyShortcutMatch? {
    guard let recordedShortcut = StoredShortcut.from(event: event) else { return nil }

    for action in LineyShortcutAction.allCases {
        guard let effectiveShortcut = LineyKeyboardShortcuts.effectiveShortcut(for: action, in: settings) else {
            continue
        }

        if action.usesNumberedDigitMatching {
            guard let tabNumber = Int(recordedShortcut.key),
                  (1...9).contains(tabNumber),
                  action.normalizedRecordedShortcut(recordedShortcut) == effectiveShortcut else {
                continue
            }
            return LineyShortcutMatch(action: action, tabNumber: tabNumber)
        }

        if recordedShortcut == effectiveShortcut {
            return LineyShortcutMatch(action: action, tabNumber: nil)
        }
    }

    return nil
}

nonisolated struct GitHubAuthStatus: Codable, Hashable {
    var username: String
    var host: String
}

nonisolated struct GitHubPullRequestActor: Codable, Hashable, Identifiable {
    var login: String

    var id: String { login }
}

nonisolated struct GitHubPullRequestReviewSummary: Codable, Hashable, Identifiable {
    var author: GitHubPullRequestActor?
    var state: String
    var submittedAt: String?

    var id: String {
        [author?.login ?? "", state, submittedAt ?? ""].joined(separator: "|")
    }

    var normalizedState: String {
        state.uppercased()
    }
}

nonisolated struct GitHubPullRequestSummary: Codable, Hashable {
    var number: Int
    var title: String
    var url: String
    var state: String
    var isDraft: Bool
    var headRefName: String?
    var mergeStateStatus: String?
    var reviewDecision: String?
    var reviewRequests: [GitHubPullRequestActor]
    var latestReviews: [GitHubPullRequestReviewSummary]
    var assignees: [GitHubPullRequestActor]

    var isOpen: Bool {
        state.uppercased() == "OPEN"
    }

    var mergeReadiness: GitHubMergeReadiness {
        guard isOpen else { return .closed }
        if isDraft {
            return .draft
        }

        let review = (reviewDecision ?? "").uppercased()
        if review == "CHANGES_REQUESTED" {
            return .changesRequested
        }

        switch (mergeStateStatus ?? "").uppercased() {
        case "CLEAN", "HAS_HOOKS":
            return .ready
        case "BEHIND":
            return .behind
        case "BLOCKED":
            return .blocked
        case "DIRTY":
            return .conflicted
        case "UNKNOWN", "":
            return .checking
        default:
            return .blocked
        }
    }

    var requestedReviewerLogins: [String] {
        Self.uniqueLogins(reviewRequests.map(\.login))
    }

    var assigneeLogins: [String] {
        Self.uniqueLogins(assignees.map(\.login))
    }

    var changesRequestedByLogins: [String] {
        Self.uniqueLogins(
            latestReviews.compactMap { review in
                review.normalizedState == "CHANGES_REQUESTED" ? review.author?.login : nil
            }
        )
    }

    var approvedByLogins: [String] {
        Self.uniqueLogins(
            latestReviews.compactMap { review in
                review.normalizedState == "APPROVED" ? review.author?.login : nil
            }
        )
    }

    var needsReviewerAttention: Bool {
        !requestedReviewerLogins.isEmpty || !changesRequestedByLogins.isEmpty
    }

    private static func uniqueLogins(_ values: [String]) -> [String] {
        Array(
            Set(
                values
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted()
    }
}

nonisolated enum GitHubMergeReadiness: String, Codable, Hashable {
    case ready
    case draft
    case changesRequested
    case behind
    case conflicted
    case blocked
    case checking
    case closed

    var label: String {
        switch self {
        case .ready:
            return "ready"
        case .draft:
            return "draft"
        case .changesRequested:
            return "changes"
        case .behind:
            return "behind"
        case .conflicted:
            return "conflict"
        case .blocked:
            return "blocked"
        case .checking:
            return "checking"
        case .closed:
            return "closed"
        }
    }
}

nonisolated struct GitHubPullRequestCheck: Codable, Hashable, Identifiable {
    var id: String { [name, workflow ?? "", state, link ?? ""].joined(separator: "|") }
    var name: String
    var workflow: String?
    var state: String
    var bucket: String
    var link: String?
    var description: String?

    var isFailing: Bool {
        bucket == "fail" || bucket == "cancel"
    }

    var isPending: Bool {
        bucket == "pending"
    }
}

nonisolated struct GitHubPullRequestChecksSummary: Codable, Hashable {
    var passingCount: Int
    var failingCount: Int
    var pendingCount: Int
    var skippedCount: Int
    var failingChecks: [GitHubPullRequestCheck]

    static let empty = GitHubPullRequestChecksSummary(
        passingCount: 0,
        failingCount: 0,
        pendingCount: 0,
        skippedCount: 0,
        failingChecks: []
    )

    var compactLabel: String? {
        let parts = [
            failingCount > 0 ? "\(failingCount)f" : nil,
            pendingCount > 0 ? "\(pendingCount)p" : nil,
            passingCount > 0 ? "\(passingCount)ok" : nil,
        ].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " ")
    }
}

nonisolated struct GitHubWorkflowRunSummary: Codable, Hashable {
    var id: Int
    var name: String
    var title: String
    var status: String
    var conclusion: String?
    var url: String?

    var statusLabel: String {
        if let conclusion, !conclusion.isEmpty {
            return conclusion.uppercased()
        }
        return status.uppercased()
    }

    var isFailing: Bool {
        let normalized = (conclusion ?? "").lowercased()
        return normalized == "failure" || normalized == "cancelled" || normalized == "timed_out"
    }

    var isPending: Bool {
        let normalizedStatus = status.lowercased()
        return normalizedStatus == "queued" || normalizedStatus == "in_progress" || normalizedStatus == "waiting"
    }
}

nonisolated struct GitHubWorktreeStatus: Codable, Hashable {
    var pullRequest: GitHubPullRequestSummary?
    var checksSummary: GitHubPullRequestChecksSummary?
    var latestRun: GitHubWorkflowRunSummary?
}

enum GitHubIntegrationState: Hashable {
    case unknown
    case disabled
    case unavailable
    case unauthorized
    case authorized(GitHubAuthStatus)

    var summary: String {
        switch self {
        case .unknown:
            return "Checking GitHub"
        case .disabled:
            return "GitHub disabled"
        case .unavailable:
            return "`gh` unavailable"
        case .unauthorized:
            return "`gh` not logged in"
        case .authorized(let auth):
            return "\(auth.username)@\(auth.host)"
        }
    }
}
