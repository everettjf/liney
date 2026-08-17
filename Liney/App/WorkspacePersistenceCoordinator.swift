//
//  WorkspacePersistenceCoordinator.swift
//  Liney
//

import Foundation

/// Owns persistence mechanics so WorkspaceStore only decides when a state
/// transition should be saved or restored.
nonisolated final class WorkspacePersistenceCoordinator: @unchecked Sendable {
    private let workspacePersistence: WorkspaceStatePersistence
    private let settingsPersistence: AppSettingsPersistence

    init(
        workspacePersistence: WorkspaceStatePersistence = WorkspaceStatePersistence(),
        settingsPersistence: AppSettingsPersistence = AppSettingsPersistence()
    ) {
        self.workspacePersistence = workspacePersistence
        self.settingsPersistence = settingsPersistence
    }

    @MainActor func loadWorkspaceState() -> PersistenceLoadResult<PersistedWorkspaceState> {
        workspacePersistence.loadWithRecovery()
    }

    @MainActor func loadAppSettings() -> PersistenceLoadResult<AppSettings> {
        settingsPersistence.loadWithRecovery()
    }

    @MainActor func saveWorkspaceState(
        _ state: PersistedWorkspaceState,
        onError: (@Sendable (Error) -> Void)? = nil
    ) {
        workspacePersistence.save(state, onError: onError)
    }

    @MainActor func saveAppSettings(
        _ settings: AppSettings,
        onError: (@Sendable (Error) -> Void)? = nil
    ) {
        settingsPersistence.save(settings, onError: onError)
    }

    func flushPendingSync() {
        workspacePersistence.flushPendingSync()
        settingsPersistence.flushPendingSync()
    }
}
