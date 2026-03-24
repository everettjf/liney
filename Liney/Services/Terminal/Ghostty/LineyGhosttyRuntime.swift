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

    var needsConfirmQuit: Bool {
        guard let app else { return false }
        return ghostty_app_needs_confirm_quit(app)
    }

    private override init() {
        super.init()
        LineyGhosttyBootstrap.initialize()

        guard let configuration = ghostty_config_new() else {
            fatalError("Unable to allocate libghostty config")
        }
        ghostty_config_load_default_files(configuration)
        ghostty_config_finalize(configuration)
        config = configuration

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

        guard let app = ghostty_app_new(&runtimeConfiguration, configuration) else {
            fatalError("Unable to initialize libghostty runtime")
        }
        self.app = app
        ghostty_app_set_focus(app, NSApp.isActive)
        installObservers()
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
        _ userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        state: UnsafeMutableRawPointer?
    ) -> Bool {
        let controllerAddress = pointerAddress(userdata)
        let stateAddress = pointerAddress(state)
        return onMainSync {
            guard let controller = controller(fromAddress: controllerAddress),
                  let pasteboard = lineyGhosttyPasteboard(for: location),
                  let value = pasteboard.lineyGhosttyBestString else {
                return false
            }

            controller.completeClipboardRequest(
                value,
                state: pointer(from: stateAddress),
                confirmed: false
            )
            return true
        }
    }

    nonisolated fileprivate static func confirmReadClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        string: UnsafePointer<CChar>?,
        state: UnsafeMutableRawPointer?,
        request: ghostty_clipboard_request_e
    ) {
        guard let string else { return }
        let text = String(cString: string)
        let controllerAddress = pointerAddress(userdata)
        let stateAddress = pointerAddress(state)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard let controller = controller(fromAddress: controllerAddress) else { return }
                controller.confirmClipboardRead(
                    text: text,
                    state: pointer(from: stateAddress),
                    request: request
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

        let items = (0..<count).compactMap { index -> LineyGhosttyClipboardPayload? in
            let entry = content[index]
            guard let mime = entry.mime, let data = entry.data else { return nil }
            return LineyGhosttyClipboardPayload(mimeType: String(cString: mime), text: String(cString: data))
        }
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

    nonisolated fileprivate static func closeSurface(_ userdata: UnsafeMutableRawPointer?) {
        let controllerAddress = pointerAddress(userdata)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard let controller = controller(fromAddress: controllerAddress) else { return }
                controller.handleManagedProcessExit(exitCode: nil)
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
    _ userdata: UnsafeMutableRawPointer?,
    _ location: ghostty_clipboard_e,
    _ state: UnsafeMutableRawPointer?
) -> Bool {
    LineyGhosttyRuntime.readClipboard(userdata, location: location, state: state)
}

nonisolated private func lineyGhosttyConfirmReadClipboardCallback(
    _ userdata: UnsafeMutableRawPointer?,
    _ string: UnsafePointer<CChar>?,
    _ state: UnsafeMutableRawPointer?,
    _ request: ghostty_clipboard_request_e
) {
    LineyGhosttyRuntime.confirmReadClipboard(userdata, string: string, state: state, request: request)
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

nonisolated private func lineyGhosttyCloseSurfaceCallback(_ userdata: UnsafeMutableRawPointer?, _: Bool) {
    LineyGhosttyRuntime.closeSurface(userdata)
}
