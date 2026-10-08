//
//  LineyGhosttyRuntime.swift
//  Liney
//
//  Author: everettjf
//

@preconcurrency import AppKit
import Foundation
import GhosttyKit

@MainActor
final class LineyGhosttyRuntime: NSObject {
    static let shared = LineyGhosttyRuntime()

    var config: ghostty_config_t!
    var app: ghostty_app_t!
    private var appSettingsObserver: NSObjectProtocol?

    /// Current terminal background opacity (0.5...1). Surface views read this
    /// to decide whether their backing layer should stay opaque or go clear so
    /// Ghostty's `background-opacity` is the sole source of translucency.
    private(set) var terminalBackgroundOpacity: CGFloat = 1

    var needsConfirmQuit: Bool {
        guard let app else { return false }
        return ghostty_app_needs_confirm_quit(app)
    }

    private override init() {
        super.init()
        LineyGhosttyBootstrap.initialize()

        let initialSettings = AppSettingsPersistence().load()
        terminalBackgroundOpacity = CGFloat(initialSettings.terminalBackgroundOpacity)
        config = Self.makeConfig(for: initialSettings)

        var runtimeConfiguration = ghostty_runtime_config_s(
            userdata: Unmanaged.passUnretained(self).toOpaque(),
            supports_selection_clipboard: true,
            wakeup_cb: lineyGhosttyWakeupCallback,
            action_cb: lineyGhosttyActionCallback,
            read_clipboard_cb: lineyGhosttyReadClipboardCallback,
            confirm_read_clipboard_cb: lineyGhosttyConfirmReadClipboardCallback,
            write_clipboard_cb: lineyGhosttyWriteClipboardCallback,
            close_surface_cb: lineyGhosttyCloseSurfaceCallback
        )

        guard let app = ghostty_app_new(&runtimeConfiguration, config) else {
            fatalError("Unable to initialize libghostty runtime")
        }
        self.app = app
        ghostty_app_set_focus(app, NSApp.isActive)
        installObservers()
    }

    deinit {
        if let appSettingsObserver {
            NotificationCenter.default.removeObserver(appSettingsObserver)
        }
        if let app {
            ghostty_app_free(app)
        }
        if let config {
            ghostty_config_free(config)
        }
    }

    func tick() {
        ghostty_app_tick(app)
    }

    private func installObservers() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(keyboardSelectionDidChange(_:)),
            name: NSTextInputContext.keyboardSelectionDidChangeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(applicationDidResignActive(_:)),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        appSettingsObserver = center.addObserver(
            forName: .lineyAppSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let settings = notification.object as? AppSettings else {
                return
            }
            Task { @MainActor [weak self] in
                self?.apply(settings: settings)
            }
        }
    }

    @objc private func keyboardSelectionDidChange(_ notification: Notification) {
        ghostty_app_keyboard_changed(app)
    }

    @objc private func applicationDidBecomeActive(_ notification: Notification) {
        ghostty_app_set_focus(app, true)
    }

    @objc private func applicationDidResignActive(_ notification: Notification) {
        ghostty_app_set_focus(app, false)
    }

    private func apply(settings: AppSettings) {
        terminalBackgroundOpacity = CGFloat(settings.terminalBackgroundOpacity)
        let nextConfig = Self.makeConfig(for: settings)
        ghostty_app_update_config(app, nextConfig)
        for controller in LineyGhosttyControllerRegistry.shared.liveControllers() {
            controller.applyConfig(nextConfig)
        }

        if let previousConfig = config {
            ghostty_config_free(previousConfig)
        }
        config = nextConfig
    }

    private static func makeConfig(for settings: AppSettings) -> ghostty_config_t {
        do {
            return try LineyGhosttyConfigManager.buildConfig(settings: settings)
        } catch {
            fatalError("Unable to configure libghostty: \(error.localizedDescription)")
        }
    }

    nonisolated fileprivate static func wakeup(_ userdata: UnsafeMutableRawPointer?) {
        guard let userdata else { return }
        let runtime = Unmanaged<LineyGhosttyRuntime>.fromOpaque(userdata).takeUnretainedValue()
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                runtime.tick()
            }
        }
    }

    nonisolated fileprivate static func handleAction(
        _ app: ghostty_app_t?,
        target: ghostty_target_s,
        action: ghostty_action_s
    ) -> Bool {
        let appAddress = pointerAddress(app)
        return onMainSync {
            switch target.tag {
            case GHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else {
                    return false
                }
                let userdataAddress = pointerAddress(ghostty_surface_userdata(surface))
                guard let controller = LineyGhosttyControllerRegistry.shared.controller(for: userdataAddress) else {
                    return false
                }
                return controller.handleGhosttyAction(action, on: surface)

            case GHOSTTY_TARGET_APP:
                return handleAppAction(pointer(from: appAddress), action: action)

            default:
                return false
            }
        }
    }

    private static func handleAppAction(_ app: ghostty_app_t?, action: ghostty_action_s) -> Bool {
        switch action.tag {
        case GHOSTTY_ACTION_OPEN_URL:
            guard let urlCString = action.action.open_url.url else { return false }
            let value = String(cString: urlCString)
            let url: URL
            if let candidate = URL(string: value), candidate.scheme != nil {
                url = candidate
            } else {
                url = URL(fileURLWithPath: NSString(string: value).expandingTildeInPath)
            }
            NSWorkspace.shared.open(url)
            return true

        case GHOSTTY_ACTION_RING_BELL:
            NSSound.beep()
            return true

        case GHOSTTY_ACTION_OPEN_CONFIG:
            if let app {
                ghostty_app_open_config(app)
                return true
            }
            return false

        default:
            return false
        }
    }

    nonisolated fileprivate static func readClipboard(
        _ userdata: UnsafeMutableRawPointer?, location: ghostty_clipboard_e,
        state: UnsafeMutableRawPointer?, mimes: UnsafePointer<UnsafePointer<CChar>?>?,
        count: Int, list: Bool
    ) -> ghostty_clipboard_read_result_e {
        let requested = lineyGhosttyCopyClipboardMimes(mimes, count: count)
        let controllerAddress = pointerAddress(userdata)
        let stateAddress = pointerAddress(state)
        return onMainSync {
            guard let controller = controller(fromAddress: controllerAddress),
                  let pasteboard = lineyGhosttyPasteboard(for: location) else {
                return GHOSTTY_CLIPBOARD_READ_UNSUPPORTED
            }
            let value = pasteboard.lineyGhosttyBestString
            // Preserve Liney's text clipboard support; do not read unrelated
            // representations simply because a terminal requested another MIME.
            var seen = Set<String>()
            let items = requested.compactMap { mime -> LineyGhosttyClipboardPayload? in
                guard seen.insert(mime).inserted, let value else { return nil }
                let item = LineyGhosttyClipboardPayload(mimeType: mime, text: value)
                return item.isPlainText ? item : nil
            }
            guard !items.isEmpty || list else { return GHOSTTY_CLIPBOARD_READ_UNAVAILABLE }
            let available = list && value != nil ? ["text/plain", "text/plain;charset=utf-8"] : []
            controller.completeClipboardRequest(
                items: items, available: available, state: pointer(from: stateAddress), confirmed: false
            )
            return GHOSTTY_CLIPBOARD_READ_STARTED
        }
    }

    nonisolated fileprivate static func confirmReadClipboard(
        _ userdata: UnsafeMutableRawPointer?, confirm: UnsafePointer<ghostty_clipboard_confirm_s>?,
        state: UnsafeMutableRawPointer?, request: ghostty_clipboard_request_e
    ) {
        let controllerAddress = pointerAddress(userdata)
        let stateAddress = pointerAddress(state)
        guard let confirm else {
            onMainSync { controller(fromAddress: controllerAddress)?.denyClipboardRequest(state: pointer(from: stateAddress)) }
            return
        }
        let items = lineyGhosttyCopyClipboardContents(confirm.pointee.contents, count: confirm.pointee.contents_len)
        let available = lineyGhosttyCopyClipboardMimes(confirm.pointee.available, count: confirm.pointee.available_len)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard let controller = controller(fromAddress: controllerAddress) else { return }
                controller.confirmClipboardRead(
                    items: items, available: available, state: pointer(from: stateAddress), request: request
                )
            }
        }
    }

    nonisolated fileprivate static func writeClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        content: UnsafePointer<ghostty_clipboard_content_s>?,
        count: Int,
        confirm: Bool
    ) {
        guard let content, count > 0 else { return }

        let items = lineyGhosttyCopyClipboardContents(content, count: count)
        guard !items.isEmpty else { return }

        if confirm {
            let controllerAddress = pointerAddress(userdata)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let controller = controller(fromAddress: controllerAddress) else { return }
                    controller.confirmClipboardWrite(items: items, location: location)
                }
            }
            return
        }

        onMainSync {
            guard let pasteboard = lineyGhosttyPasteboard(for: location) else { return }
            writeClipboard(items, to: pasteboard)
        }
    }

    private static func writeClipboard(_ items: [LineyGhosttyClipboardPayload], to pasteboard: NSPasteboard) {
        lineyGhosttyWriteClipboard(items, to: pasteboard)
    }

    nonisolated fileprivate static func closeSurface(_ userdata: UnsafeMutableRawPointer?, processAlive: Bool) {
        let controllerAddress = pointerAddress(userdata)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard let controller = controller(fromAddress: controllerAddress) else { return }
                controller.handleSurfaceClose(processAlive: processAlive)
            }
        }
    }

    private static func controller(from userdata: UnsafeMutableRawPointer?) -> LineyGhosttyController? {
        LineyGhosttyControllerRegistry.shared.controller(for: pointerAddress(userdata))
    }

    private static func controller(fromAddress address: UInt?) -> LineyGhosttyController? {
        controller(from: pointer(from: address))
    }

    nonisolated private static func pointerAddress<T>(_ pointer: UnsafeMutablePointer<T>?) -> UInt? {
        pointer.map { UInt(bitPattern: $0) }
    }

    nonisolated private static func pointerAddress<T>(_ pointer: UnsafePointer<T>?) -> UInt? {
        pointer.map { UInt(bitPattern: $0) }
    }

    nonisolated private static func pointerAddress(_ pointer: UnsafeMutableRawPointer?) -> UInt? {
        pointer.map { UInt(bitPattern: $0) }
    }

    nonisolated private static func pointer<T>(from address: UInt?) -> UnsafeMutablePointer<T>? {
        guard let address else { return nil }
        return UnsafeMutablePointer<T>(bitPattern: address)
    }

    nonisolated private static func pointer(from address: UInt?) -> UnsafeMutableRawPointer? {
        guard let address else { return nil }
        return UnsafeMutableRawPointer(bitPattern: address)
    }

    nonisolated private static func onMainSync<T: Sendable>(_ body: @MainActor () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                body()
            }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                body()
            }
        }
    }
}

nonisolated private func lineyGhosttyWakeupCallback(_ userdata: UnsafeMutableRawPointer?) {
    LineyGhosttyRuntime.wakeup(userdata)
}

nonisolated private func lineyGhosttyActionCallback(
    _ app: ghostty_app_t?,
    _ target: ghostty_target_s,
    _ action: ghostty_action_s
) -> Bool {
    LineyGhosttyRuntime.handleAction(app, target: target, action: action)
}

nonisolated private func lineyGhosttyReadClipboardCallback(
    _ userdata: UnsafeMutableRawPointer?, _ location: ghostty_clipboard_e,
    _ state: UnsafeMutableRawPointer?, _ mimes: UnsafePointer<UnsafePointer<CChar>?>?,
    _ count: Int, _ list: Bool
) -> ghostty_clipboard_read_result_e {
    LineyGhosttyRuntime.readClipboard(userdata, location: location, state: state, mimes: mimes, count: count, list: list)
}

nonisolated private func lineyGhosttyConfirmReadClipboardCallback(
    _ userdata: UnsafeMutableRawPointer?, _ confirm: UnsafePointer<ghostty_clipboard_confirm_s>?,
    _ state: UnsafeMutableRawPointer?, _ request: ghostty_clipboard_request_e
) {
    LineyGhosttyRuntime.confirmReadClipboard(userdata, confirm: confirm, state: state, request: request)
}

nonisolated private func lineyGhosttyWriteClipboardCallback(
    _ userdata: UnsafeMutableRawPointer?,
    _ location: ghostty_clipboard_e,
    _ content: UnsafePointer<ghostty_clipboard_content_s>?,
    _ count: Int,
    _ confirm: Bool
) {
    LineyGhosttyRuntime.writeClipboard(userdata, location: location, content: content, count: count, confirm: confirm)
}

nonisolated private func lineyGhosttyCloseSurfaceCallback(_ userdata: UnsafeMutableRawPointer?, processAlive: Bool) {
    LineyGhosttyRuntime.closeSurface(userdata, processAlive: processAlive)
}
