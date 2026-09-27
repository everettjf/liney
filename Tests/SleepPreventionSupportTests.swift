//
//  SleepPreventionSupportTests.swift
//  LineyTests
//
//  Author: everettjf
//

import AppKit
import XCTest
import IOKit.pwr_mgt
@testable import Liney

@MainActor
final class SleepPreventionSupportTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        LocalizationManager.shared.updateSelectedLanguage(.english)
    }

    override func tearDown() async throws {
        LocalizationManager.shared.updateSelectedLanguage(.automatic)
        try await super.tearDown()
    }
    
    func testSleepPreventionDurationsMatchExpectedSeconds() {
        XCTAssertEqual(SleepPreventionDurationOption.oneHour.duration, 3_600)
        XCTAssertEqual(SleepPreventionDurationOption.twelveHours.duration, 43_200)
        XCTAssertEqual(SleepPreventionDurationOption.threeDays.duration, 259_200)
        XCTAssertNil(SleepPreventionDurationOption.forever.duration)
    }

    func testDurationFormattingUsesLargestUnits() {
        let duration: TimeInterval = 95_400

        XCTAssertEqual(SleepPreventionFormat.duration(duration), "1d 2h")
    }

    func testForeverSessionUsesOnStatus() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let session = SleepPreventionSession(option: .forever, startedAt: now, expiresAt: nil)

        let description = session.remainingDescription(relativeTo: now)
        XCTAssertEqual(description, "On")
    }
}


@MainActor
final class AutoLockPreventionControllerTests: XCTestCase {
    func testRefreshTracksLatestAssertionAndStopReleasesItOnce() {
        var receivedIDs: [IOPMAssertionID] = []
        var releasedIDs: [IOPMAssertionID] = []
        var states: [Bool] = []
        let controller = AutoLockPreventionController(
            declareActivity: { id in
                receivedIDs.append(id)
                id = IOPMAssertionID(receivedIDs.count)
                return kIOReturnSuccess
            },
            releaseAssertion: { releasedIDs.append($0) }
        )
        controller.onChange = { states.append($0) }
        controller.start()
        controller.start()
        controller.refreshActivity()
        controller.stop()
        controller.stop()
        controller.refreshActivity()
        XCTAssertEqual(receivedIDs, [IOPMAssertionID(kIOPMNullAssertionID), 1])
        XCTAssertEqual(releasedIDs, [2])
        XCTAssertEqual(states, [true, false])
        XCTAssertFalse(controller.isActive)
    }

    func testFailedRefreshDisablesProtectionAndReportsFailure() {
        var calls = 0
        var releasedIDs: [IOPMAssertionID] = []
        var failure: IOReturn?
        let controller = AutoLockPreventionController(
            declareActivity: { id in
                calls += 1
                id = 42
                return calls == 1 ? kIOReturnSuccess : kIOReturnError
            },
            releaseAssertion: { releasedIDs.append($0) }
        )
        controller.onFailure = { failure = $0 }
        controller.start()
        controller.refreshActivity()
        controller.refreshActivity()
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(failure, kIOReturnError)
        XCTAssertEqual(releasedIDs, [42])
        XCTAssertEqual(calls, 2)
    }

    func testTimedProtectionStopsRefreshingAtDeadline() {
        var calls = 0
        var releasedIDs: [IOPMAssertionID] = []
        let deadline = Date(timeIntervalSince1970: 2_000)
        let controller = AutoLockPreventionController(
            declareActivity: { id in
                calls += 1
                id = 42
                return kIOReturnSuccess
            },
            releaseAssertion: { releasedIDs.append($0) }
        )
        controller.start(expiresAt: deadline)
        controller.refreshActivity(now: deadline.addingTimeInterval(-1))
        XCTAssertTrue(controller.isActive)
        controller.refreshActivity(now: deadline)
        controller.refreshActivity(now: deadline.addingTimeInterval(20))
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(releasedIDs, [42])
    }

    func testSleepOnlyAllowsDisplaySleepAndModesHaveStableOrder() {
        XCTAssertEqual(SleepPreventionMode.allCases, [.sleep, .sleepAndLock])
        XCTAssertEqual(SleepPreventionMode.sleep.caffeinateArguments, ["-ims"])
        XCTAssertEqual(SleepPreventionMode.sleepAndLock.caffeinateArguments, ["-dims"])
    }

    func testStartFailureDoesNotReportActive() {
        var states: [Bool] = []
        var failure: IOReturn?
        let controller = AutoLockPreventionController(
            declareActivity: { _ in kIOReturnError },
            releaseAssertion: { _ in XCTFail("No assertion should be released") }
        )
        controller.onChange = { states.append($0) }
        controller.onFailure = { failure = $0 }
        controller.start()
        XCTAssertFalse(controller.isActive)
        XCTAssertTrue(states.isEmpty)
        XCTAssertEqual(failure, kIOReturnError)
    }
}


@MainActor
final class ApplicationMenuTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        LocalizationManager.shared.updateSelectedLanguage(.english)
    }

    override func tearDown() async throws {
        LocalizationManager.shared.updateSelectedLanguage(.automatic)
        try await super.tearDown()
    }

    func testSleepMenuTracksActiveModeAndDuration() throws {
        let store = WorkspaceStore(persistsWorkspaceState: false)
        let inactive = SleepPreventionMenu.make(for: store)
        XCTAssertEqual(inactive.items.map(\.title), ["Prevent Sleep", "Prevent Sleep and Lock"])
        XCTAssertEqual(inactive.items.compactMap { $0.submenu?.items.count }, [8, 8])
        XCTAssertTrue(inactive.items.allSatisfy { $0.state == .off })

        store.sleepPreventionSession = SleepPreventionSession(
            option: .twoHours, startedAt: Date(), expiresAt: Date().addingTimeInterval(7200), mode: .sleepAndLock
        )
        let active = SleepPreventionMenu.make(for: store)
        let combined = try XCTUnwrap(active.items.last)
        XCTAssertEqual(combined.state, .on)
        XCTAssertEqual(combined.submenu?.items.filter { $0.state == .on }.map(\.title), ["2 Hours"])
        XCTAssertTrue(active.items.contains { $0.title == "Stop Current Mode" })
        store.sleepPreventionSession = nil
    }

    func testMenuNavigationKeepsShortcutsAndRefreshesActiveStore() throws {
        let original = NSApp.mainMenu
        let originalWindows = NSApp.windowsMenu
        let originalHelp = NSApp.helpMenu
        let originalServices = NSApp.servicesMenu
        defer {
            NSApp.mainMenu = original
            NSApp.windowsMenu = originalWindows
            NSApp.helpMenu = originalHelp
            NSApp.servicesMenu = originalServices
        }
        let controller = ApplicationMenuController()
        let store = WorkspaceStore(persistsWorkspaceState: false)
        var activeStore: WorkspaceStore?
        controller.activeWorkspaceStoreProvider = { activeStore }
        controller.installMainMenu(appName: "Liney", target: NSObject(), settings: AppSettings())
        let main = try XCTUnwrap(NSApp.mainMenu)
        let view = try XCTUnwrap(main.item(withTitle: "View")?.submenu)
        let workspace = try XCTUnwrap(main.item(withTitle: "Workspace")?.submenu)
        let window = try XCTUnwrap(main.item(withTitle: "Window")?.submenu)
        XCTAssertNil(view.item(withTitle: "Open Diff"))
        XCTAssertNotNil(workspace.item(withTitle: "Open Diff"))
        let nextTab = try XCTUnwrap(window.items.first { ($0.representedObject as? String) == LineyShortcutAction.nextTab.rawValue })
        XCTAssertFalse(nextTab.keyEquivalent.isEmpty)
        let canvas = try XCTUnwrap(view.item(withTitle: "Canvas"))
        XCTAssertFalse(controller.validateMenuItem(canvas))
        activeStore = store
        store.isCanvasPresented = true
        XCTAssertTrue(controller.validateMenuItem(canvas))
        XCTAssertEqual(canvas.state, .on)
        store.dispatch(.toggleOverview)
        XCTAssertFalse(store.isCanvasPresented)
        XCTAssertTrue(store.isOverviewPresented)
        let appMenu = try XCTUnwrap(main.items.first?.submenu)
        controller.menuNeedsUpdate(appMenu)
        let sleep = try XCTUnwrap(appMenu.item(withTitle: "Sleep and Auto-Lock Prevention")?.submenu)
        XCTAssertEqual(sleep.items.count, 2)
        activeStore = nil
        controller.menuNeedsUpdate(appMenu)
        XCTAssertTrue(sleep.items.isEmpty)
    }
}
