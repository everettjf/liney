//
//  SleepPreventionSupport.swift
//  Liney
//
//  Author: everettjf
//

import Foundation
import IOKit.pwr_mgt

nonisolated enum SleepPreventionDurationOption: String, CaseIterable, Identifiable, Hashable {
    case oneHour
    case twoHours
    case threeHours
    case sixHours
    case twelveHours
    case oneDay
    case threeDays
    case forever

    var id: String { rawValue }

    @MainActor
    var title: String {
        switch self {
        case .oneHour:
            return LocalizationManager.shared.string("main.sleepPrevention.option.oneHour")
        case .twoHours:
            return LocalizationManager.shared.string("main.sleepPrevention.option.twoHours")
        case .threeHours:
            return LocalizationManager.shared.string("main.sleepPrevention.option.threeHours")
        case .sixHours:
            return LocalizationManager.shared.string("main.sleepPrevention.option.sixHours")
        case .twelveHours:
            return LocalizationManager.shared.string("main.sleepPrevention.option.twelveHours")
        case .oneDay:
            return LocalizationManager.shared.string("main.sleepPrevention.option.oneDay")
        case .threeDays:
            return LocalizationManager.shared.string("main.sleepPrevention.option.threeDays")
        case .forever:
            return LocalizationManager.shared.string("main.sleepPrevention.option.forever")
        }
    }

    @MainActor
    var compactTitle: String {
        switch self {
        case .oneHour:
            return "1h"
        case .twoHours:
            return "2h"
        case .threeHours:
            return "3h"
        case .sixHours:
            return "6h"
        case .twelveHours:
            return "12h"
        case .oneDay:
            return "1d"
        case .threeDays:
            return "3d"
        case .forever:
            return LocalizationManager.shared.string("main.sleepPrevention.compact.forever")
        }
    }

    var duration: TimeInterval? {
        switch self {
        case .oneHour:
            return 60 * 60
        case .twoHours:
            return 2 * 60 * 60
        case .threeHours:
            return 3 * 60 * 60
        case .sixHours:
            return 6 * 60 * 60
        case .twelveHours:
            return 12 * 60 * 60
        case .oneDay:
            return 24 * 60 * 60
        case .threeDays:
            return 3 * 24 * 60 * 60
        case .forever:
            return nil
        }
    }
}

nonisolated enum SleepPreventionMode: CaseIterable {
    case sleep
    case sleepAndLock

    @MainActor var title: String {
        LocalizationManager.shared.string(self == .sleep
            ? "main.sleepPrevention.mode.sleep" : "main.sleepPrevention.mode.sleepAndLock")
    }

    var caffeinateArguments: [String] {
        self == .sleep ? ["-ims"] : ["-dims"]
    }
}

nonisolated struct SleepPreventionSession: Equatable {
    let option: SleepPreventionDurationOption
    let mode: SleepPreventionMode
    let startedAt: Date
    let expiresAt: Date?

    init(option: SleepPreventionDurationOption, startedAt: Date, expiresAt: Date?, mode: SleepPreventionMode = .sleep) {
        self.mode = mode
        self.option = option
        self.startedAt = startedAt
        self.expiresAt = expiresAt
    }

    var isIndefinite: Bool {
        expiresAt == nil
    }

    @MainActor
    func compactRemainingDescription(relativeTo now: Date) -> String {
        guard let expiresAt else {
            return LocalizationManager.shared.string("main.sleepPrevention.compact.on")
        }
        let remaining = max(0, expiresAt.timeIntervalSince(now))
        return SleepPreventionFormat.duration(remaining)
    }

    @MainActor
    func remainingDescription(relativeTo now: Date) -> String {
        let compact = compactRemainingDescription(relativeTo: now)
        if compact == LocalizationManager.shared.string("main.sleepPrevention.compact.on") {
            return compact
        }
        return l10nFormat(
            LocalizationManager.shared.string("main.sleepPrevention.remaining.leftFormat"),
            arguments: [compact]
        )
    }
}

nonisolated enum SleepPreventionStopReason: Equatable {
    case userInitiated
    case completed
    case failed(String)
}

nonisolated enum SleepPreventionControllerEvent: Equatable {
    case started(SleepPreventionSession)
    case stopped(SleepPreventionStopReason)
}

nonisolated enum SleepPreventionFormat {
    @MainActor
    static func duration(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(max(0, interval.rounded(.down)))
        let days = totalSeconds / 86_400
        let hours = (totalSeconds % 86_400) / 3_600
        let minutes = (totalSeconds % 3_600) / 60

        var parts: [String] = []
        if days > 0 {
            parts.append("\(days)d")
        }
        if hours > 0 {
            parts.append("\(hours)h")
        }
        if minutes > 0 && parts.count < 2 {
            parts.append("\(minutes)m")
        }

        if parts.isEmpty {
            return LocalizationManager.shared.string("main.sleepPrevention.remaining.underOneMinute")
        }
        return parts.prefix(2).joined(separator: " ")
    }
}

@MainActor
final class SleepPreventionController {
    var onEvent: ((SleepPreventionControllerEvent) -> Void)?

    private var process: Process?
    private var currentSession: SleepPreventionSession?
    private let autoLockController = AutoLockPreventionController()

    init() {
        autoLockController.onFailure = { [weak self] code in
            guard let self else { return }
            self.stopCurrentProcess(emitStoppedEvent: false)
            self.onEvent?(.stopped(.failed(l10nFormat(
                LocalizationManager.shared.string("main.autoLockPrevention.error"),
                arguments: [String(code)]
            ))))
        }
    }

    deinit {
        process?.terminate()
    }

    func start(_ option: SleepPreventionDurationOption, mode: SleepPreventionMode = .sleep) throws {
        stopCurrentProcess(emitStoppedEvent: false)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")

        var arguments = mode.caffeinateArguments
        if let duration = option.duration {
            arguments.append("-t")
            arguments.append(String(max(1, Int(duration.rounded(.up)))))
        }
        process.arguments = arguments

        process.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                guard let self,
                      self.process === process else { return }

                self.autoLockController.stop()
                self.process = nil
                self.currentSession = nil

                if process.terminationReason == .exit, process.terminationStatus == 0 {
                    self.onEvent?(.stopped(.completed))
                } else {
                    self.onEvent?(.stopped(.failed("caffeinate exited with status \(process.terminationStatus).")))
                }
            }
        }

        do {
            try process.run()
        } catch {
            onEvent?(.stopped(.failed(error.localizedDescription)))
            throw error
        }

        let startedAt = Date()
        let session = SleepPreventionSession(
            option: option,
            startedAt: startedAt,
            expiresAt: option.duration.map { startedAt.addingTimeInterval($0) },
            mode: mode
        )

        self.process = process
        self.currentSession = session
        if mode == .sleepAndLock {
            autoLockController.start(expiresAt: session.expiresAt)
            guard autoLockController.isActive else { return }
        }
        onEvent?(.started(session))
    }

    func stop() {
        stopCurrentProcess(emitStoppedEvent: true)
    }

    private func stopCurrentProcess(emitStoppedEvent: Bool) {
        autoLockController.stop()
        let previousProcess = process
        let hadActiveSession = currentSession != nil

        process = nil
        currentSession = nil

        if emitStoppedEvent, hadActiveSession {
            onEvent?(.stopped(.userInitiated))
        }

        guard let previousProcess, previousProcess.isRunning else { return }
        previousProcess.terminate()
    }
}


/// Refreshes user activity independently of the system-sleep assertion.
@MainActor
final class AutoLockPreventionController {
    typealias DeclareActivity = (inout IOPMAssertionID) -> IOReturn

    var onChange: ((Bool) -> Void)?
    var onFailure: ((IOReturn) -> Void)?
    private(set) var isActive = false
    private var assertionID = IOPMAssertionID(kIOPMNullAssertionID)
    private var timer: Timer?
    private var expiresAt: Date?
    private var activity: NSObjectProtocol?
    private let declareActivity: DeclareActivity
    private let releaseAssertion: (IOPMAssertionID) -> Void

    init(
        declareActivity: @escaping DeclareActivity = { id in
            IOPMAssertionDeclareUserActivity(
                "Liney prevent automatic screen lock" as CFString,
                kIOPMUserActiveLocal,
                &id
            )
        },
        releaseAssertion: @escaping (IOPMAssertionID) -> Void = { _ = IOPMAssertionRelease($0) }
    ) {
        self.declareActivity = declareActivity
        self.releaseAssertion = releaseAssertion
    }

    deinit {
        timer?.invalidate()
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        if assertionID != kIOPMNullAssertionID { releaseAssertion(assertionID) }
    }

    func start(expiresAt: Date? = nil) {
        guard !isActive else { return }
        self.expiresAt = expiresAt
        let result = declareActivity(&assertionID)
        guard result == kIOReturnSuccess else {
            stop()
            onFailure?(result)
            return
        }
        isActive = true
        // Keep the refresh timer running while Liney is in the background.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Prevent automatic screen lock"
        )
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshActivity() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        onChange?(true)
    }

    func refreshActivity(now: Date = Date()) {
        guard isActive else { return }
        if let expiresAt, now >= expiresAt {
            stop()
            return
        }
        let result = declareActivity(&assertionID)
        guard result != kIOReturnSuccess else { return }
        stop()
        onFailure?(result)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        expiresAt = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        if assertionID != kIOPMNullAssertionID { releaseAssertion(assertionID) }
        assertionID = IOPMAssertionID(kIOPMNullAssertionID)
        let wasActive = isActive
        isActive = false
        if wasActive { onChange?(false) }
    }
}
