# Remote Worktree & Icons Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make remote workspaces feature-equivalent to local ones: semantic icons, full git worktree listing, worktree CRUD over SSH, independent per-worktree sessions, and 5-second refresh polling.

**Architecture:** Extend the existing remote git inspection SSH command to include `git worktree list --porcelain`. Widen `supportsRepositoryFeatures` to include `.remoteServer`. Add SSH-based worktree create/remove methods. Change refresh interval constant from 30→5.

**Tech Stack:** Swift, SwiftUI, XCTest, SSH CLI (`/usr/bin/ssh`)

---

### Task 1: Extend `RemoteGitSnapshot` to include worktrees

**Files:**
- Modify: `Liney/Services/Git/GitRepositoryService.swift:43-49`
- Test: `Tests/RemoteGitInspectionTests.swift`

**Step 1: Write the failing test**

Add a new test to `RemoteGitInspectionTests.swift` that verifies `parseRemoteInspection` can parse a `__WORKTREE__` section:

```swift
func testParseRemoteGitInspectionWithWorktrees() {
    let output = """
    __BRANCH__
    main
    __HEAD__
    abc1234
    __WORKTREE__
    worktree /home/user/project
    HEAD abc1234567890abcdef1234567890abcdef12345678
    branch refs/heads/main

    worktree /home/user/project-feature
    HEAD def5678567890abcdef1234567890abcdef12345678
    branch refs/heads/feature/login

    __STATUS__
    M  file1.txt
    __AHEAD_BEHIND__
    1\t0
    """

    let snapshot = GitRepositoryService.parseRemoteInspection(output)

    XCTAssertEqual(snapshot.branch, "main")
    XCTAssertEqual(snapshot.head, "abc1234")
    XCTAssertEqual(snapshot.worktrees.count, 2)
    XCTAssertEqual(snapshot.worktrees[0].path, "/home/user/project")
    XCTAssertEqual(snapshot.worktrees[0].branch, "main")
    XCTAssertTrue(snapshot.worktrees[0].isMainWorktree)
    XCTAssertEqual(snapshot.worktrees[1].path, "/home/user/project-feature")
    XCTAssertEqual(snapshot.worktrees[1].branch, "feature/login")
    XCTAssertFalse(snapshot.worktrees[1].isMainWorktree)
    XCTAssertEqual(snapshot.changedFileCount, 1)
    XCTAssertEqual(snapshot.aheadCount, 1)
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild -project Liney.xcodeproj -scheme Liney -destination 'platform=macOS' test -only-testing:LineyTests/RemoteGitInspectionTests/testParseRemoteGitInspectionWithWorktrees 2>&1 | tail -20`
Expected: FAIL — `RemoteGitSnapshot` has no `worktrees` property

**Step 3: Write minimal implementation**

3a. Add `worktrees` field to `RemoteGitSnapshot` (line 43-49):

```swift
struct RemoteGitSnapshot {
    var branch: String
    var head: String
    var changedFileCount: Int
    var aheadCount: Int
    var behindCount: Int
    var worktrees: [WorktreeModel]
}
```

3b. Update `parseRemoteInspection` (lines 495-536) to handle `__WORKTREE__` section. The key change: accumulate worktree output lines, then call existing `parseWorktreeList`. The tricky part is that `parseWorktreeList` uses `rootPath` for `isMainWorktree` detection — for remote, use the first worktree path as root:

```swift
nonisolated static func parseRemoteInspection(_ output: String) -> RemoteGitSnapshot {
    var branch = ""
    var head = ""
    var changedFileCount = 0
    var aheadCount = 0
    var behindCount = 0
    var worktreeOutput = ""
    var currentSection = ""

    for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed {
        case "__BRANCH__", "__HEAD__", "__WORKTREE__", "__STATUS__", "__AHEAD_BEHIND__":
            currentSection = trimmed
        default:
            switch currentSection {
            case "__BRANCH__":
                let t = trimmed
                if !t.isEmpty { branch = t }
            case "__HEAD__":
                let t = trimmed
                if !t.isEmpty { head = t }
            case "__WORKTREE__":
                worktreeOutput += String(line) + "\n"
            case "__STATUS__":
                if !trimmed.isEmpty { changedFileCount += 1 }
            case "__AHEAD_BEHIND__":
                if !trimmed.isEmpty {
                    let parts = trimmed.split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
                    if parts.count >= 2 {
                        aheadCount = parts[0]
                        behindCount = parts[1]
                    }
                }
            default:
                break
            }
        }
    }

    // Derive rootPath from the first worktree entry for isMainWorktree detection
    let firstWorktreePath = worktreeOutput
        .split(separator: "\n", omittingEmptySubsequences: false)
        .first(where: { $0.hasPrefix("worktree ") })
        .map { String($0.dropFirst("worktree ".count)).trimmingCharacters(in: .whitespacesAndNewlines) }
        ?? ""
    let worktrees = parseWorktreeList(worktreeOutput, rootPath: firstWorktreePath)

    return RemoteGitSnapshot(
        branch: branch,
        head: head,
        changedFileCount: changedFileCount,
        aheadCount: aheadCount,
        behindCount: behindCount,
        worktrees: worktrees
    )
}
```

3c. Update `inspectRemoteRepository` SSH script (lines 540-545) to include `__WORKTREE__`:

```swift
let script = "cd \(remotePath) && " +
    "echo __BRANCH__ && git rev-parse --abbrev-ref HEAD 2>/dev/null && " +
    "echo __HEAD__ && git rev-parse --short HEAD 2>/dev/null && " +
    "echo __WORKTREE__ && git worktree list --porcelain 2>/dev/null && " +
    "echo __STATUS__ && git status --porcelain 2>/dev/null && " +
    "echo __AHEAD_BEHIND__ && git rev-list --left-right --count HEAD...@{upstream} 2>/dev/null || true"
```

**Step 4: Update existing tests**

Existing `parseRemoteInspection` tests need `worktrees` assertions. Add `XCTAssertTrue(snapshot.worktrees.isEmpty)` to the existing tests since they have no `__WORKTREE__` section (empty worktrees is valid).

**Step 5: Run all tests to verify they pass**

Run: `xcodebuild -project Liney.xcodeproj -scheme Liney -destination 'platform=macOS' test -only-testing:LineyTests/RemoteGitInspectionTests 2>&1 | tail -20`
Expected: ALL PASS

**Step 6: Commit**

```bash
git add Liney/Services/Git/GitRepositoryService.swift Tests/RemoteGitInspectionTests.swift
git commit -m "feat: extend remote git inspection to include worktree listing"
```

---

### Task 2: Widen `supportsRepositoryFeatures` to include remote workspaces

**Files:**
- Modify: `Liney/Domain/WorkspaceRuntime.swift:153-155`

**Step 1: Write the failing test**

Add to `Tests/RemoteWorkspaceModelTests.swift`:

```swift
func testRemoteServerSupportsRepositoryFeatures() {
    let record = WorkspaceRecord(
        id: UUID(),
        kind: .remoteServer,
        name: "remote-test",
        repositoryRoot: "/home/user/project",
        activeWorktreePath: "/home/user/project",
        worktreeStates: [],
        isSidebarExpanded: false,
        sshTarget: SSHSessionConfiguration(host: "server.example.com")
    )
    let model = WorkspaceModel(record: record)
    XCTAssertTrue(model.supportsRepositoryFeatures)
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild -project Liney.xcodeproj -scheme Liney -destination 'platform=macOS' test -only-testing:LineyTests/RemoteWorkspaceModelTests/testRemoteServerSupportsRepositoryFeatures 2>&1 | tail -20`
Expected: FAIL — `supportsRepositoryFeatures` returns false for `.remoteServer`

**Step 3: Write minimal implementation**

Change `WorkspaceRuntime.swift:153-155`:

```swift
var supportsRepositoryFeatures: Bool {
    kind == .repository || kind == .remoteServer
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild -project Liney.xcodeproj -scheme Liney -destination 'platform=macOS' test -only-testing:LineyTests/RemoteWorkspaceModelTests 2>&1 | tail -20`
Expected: PASS

**Step 5: Commit**

```bash
git add Liney/Domain/WorkspaceRuntime.swift Tests/RemoteWorkspaceModelTests.swift
git commit -m "feat: enable repository features for remote workspaces"
```

---

### Task 3: Update remote refresh to populate worktrees and use semantic icons

**Files:**
- Modify: `Liney/App/WorkspaceStore.swift:65` (refresh interval)
- Modify: `Liney/App/WorkspaceStore.swift:914-916` (icon selection)
- Modify: `Liney/App/WorkspaceStore.swift:3042-3060` (refresh logic)

**Step 1: Change refresh interval**

In `WorkspaceStore.swift:65`, change:
```swift
private static let remoteRefreshInterval: TimeInterval = 5
```

**Step 2: Update `refreshRemoteWorkspace` to populate worktrees**

Replace `refreshRemoteWorkspace` (lines 3042-3060) to merge worktrees by path (preserving stable IDs like treemux does) and populate per-worktree state:

```swift
private func refreshRemoteWorkspace(_ workspace: WorkspaceModel) async {
    guard let sshConfig = workspace.sshTarget else { return }
    let remotePath = workspace.repositoryRoot
    do {
        let snapshot = try await gitRepositoryService.inspectRemoteRepository(
            remotePath: remotePath, sshConfig: sshConfig
        )
        workspace.currentBranch = snapshot.branch
        workspace.head = snapshot.head
        workspace.hasUncommittedChanges = snapshot.changedFileCount > 0
        workspace.changedFileCount = snapshot.changedFileCount
        workspace.aheadCount = snapshot.aheadCount
        workspace.behindCount = snapshot.behindCount

        // Merge worktrees: preserve existing paths to keep stable IDs and session state
        var merged: [WorktreeModel] = []
        for newWT in snapshot.worktrees {
            if let existing = workspace.worktrees.first(where: { $0.path == newWT.path }) {
                merged.append(WorktreeModel(
                    path: existing.path,
                    branch: newWT.branch,
                    head: newWT.head,
                    isMainWorktree: newWT.isMainWorktree,
                    isLocked: newWT.isLocked,
                    lockReason: newWT.lockReason
                ))
            } else {
                merged.append(newWT)
            }
        }
        workspace.worktrees = merged

        // If active worktree was removed, fall back to repository root
        if !workspace.worktrees.contains(where: { $0.path == workspace.activeWorktreePath }) {
            workspace.activeWorktreePath = workspace.repositoryRoot
        }

        workspace.ensureKnownWorktreeStates()
        workspace.pruneWorktreeCustomizations()
    } catch {
        if AppLogger.isEnabled {
            AppLogger.workspace.error("Remote refresh failed for \(workspace.name): \(error.localizedDescription)")
        }
    }
}
```

**Step 3: Update `sidebarIcon(for workspace:)` to handle remote workspaces**

The current code at line 914-916:
```swift
func sidebarIcon(for workspace: WorkspaceModel) -> SidebarItemIcon {
    workspace.workspaceIconOverride ?? (workspace.supportsRepositoryFeatures ? appSettings.defaultRepositoryIcon : appSettings.defaultLocalTerminalIcon)
}
```

Since we changed `supportsRepositoryFeatures` to return `true` for `.remoteServer`, remote workspaces will now automatically use `defaultRepositoryIcon` (the blue branch icon). This gives them the same semantic icon generation path as local repos.

However, the `worktreeIconSeed` helper (line 942-945) uses `URL(fileURLWithPath:).lastPathComponent` which works for remote paths too since they're POSIX paths. No change needed there.

**Step 4: Verify timer tolerance**

The timer at line 3003 has `timer.tolerance = 5`. With a 5-second interval, 5 seconds of tolerance is too generous. Change to:
```swift
timer.tolerance = 1
```

**Step 5: Run full test suite**

Run: `xcodebuild -project Liney.xcodeproj -scheme Liney -destination 'platform=macOS' test 2>&1 | tail -30`
Expected: ALL PASS

**Step 6: Commit**

```bash
git add Liney/App/WorkspaceStore.swift
git commit -m "feat: populate remote worktrees on refresh, 5-second polling, semantic icons"
```

---

### Task 4: Add remote worktree creation via SSH

**Files:**
- Modify: `Liney/Services/Git/GitRepositoryService.swift` (add `createRemoteWorktree` method)
- Modify: `Liney/App/WorkspaceStore.swift` (update `createWorktree` to handle remote)
- Modify: `Liney/App/WorkspaceStore.swift` (update `presentCreateWorktree` to handle remote)
- Test: `Tests/RemoteGitInspectionTests.swift` (or new test file)

**Step 1: Add `createRemoteWorktree` method to `GitRepositoryService`**

Add after `removeWorktree` (line 406):

```swift
func createRemoteWorktree(rootPath: String, request: CreateWorktreeRequest, sshConfig: SSHSessionConfiguration) async throws {
    var gitArgs = "git worktree add"
    if request.createNewBranch {
        gitArgs += " -b '\(request.branchName)' '\(request.directoryPath)' HEAD"
    } else {
        gitArgs += " '\(request.directoryPath)' '\(request.branchName)'"
    }
    let script = "cd '\(rootPath)' && \(gitArgs)"

    var arguments = [
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=10",
    ]
    if let port = sshConfig.port {
        arguments.append(contentsOf: ["-p", "\(port)"])
    }
    if let identityFile = sshConfig.identityFilePath {
        arguments.append(contentsOf: ["-i", identityFile])
    }
    arguments.append(sshConfig.destination)
    arguments.append(script)

    let result = try await runner.run(
        executable: "/usr/bin/ssh",
        arguments: arguments,
        timeout: Self.remoteInspectTimeout
    )
    guard result.exitCode == 0 else {
        throw GitServiceError.commandFailed(
            result.stderr.nonEmptyOrFallback("Unable to create remote worktree.")
        )
    }
}
```

**Step 2: Update `createWorktree(workspaceID:draft:)` in WorkspaceStore**

Modify the method at line 2146 to handle remote workspaces. Key changes:
- Skip `FileManager.default.fileExists` check for remote (it's a local filesystem call)
- Skip `URL(fileURLWithPath:).standardizedFileURL` normalization for remote (paths are remote POSIX)
- Call `createRemoteWorktree` instead of `createWorktree` when workspace is remote
- Call `refreshRemoteWorkspace` instead of `refreshWorkspace` after creation

```swift
func createWorktree(workspaceID: UUID, draft: CreateWorktreeDraft) -> Bool {
    guard let workspace = workspaces.first(where: { $0.id == workspaceID }),
          workspace.supportsRepositoryFeatures else { return false }

    let normalizedBranchName = draft.normalizedBranchName

    guard !normalizedBranchName.isEmpty else {
        presentError(title: localized("main.error.createWorktree.title"), message: localized("main.error.createWorktree.branchRequired"))
        return false
    }
    guard !normalizedBranchName.contains(" ") else {
        presentError(title: localized("main.error.createWorktree.title"), message: localized("main.error.createWorktree.branchNoSpaces"))
        return false
    }

    let isRemote = workspace.isRemote

    let normalizedDirectoryPath: String
    if isRemote {
        normalizedDirectoryPath = draft.normalizedDirectoryPath
    } else {
        normalizedDirectoryPath = URL(fileURLWithPath: draft.normalizedDirectoryPath)
            .standardizedFileURL
            .path
    }

    guard !normalizedDirectoryPath.isEmpty else {
        presentError(title: localized("main.error.createWorktree.title"), message: localized("main.error.createWorktree.directoryRequired"))
        return false
    }

    if !isRemote {
        guard !FileManager.default.fileExists(atPath: normalizedDirectoryPath) else {
            presentError(title: localized("main.error.createWorktree.title"), message: localized("main.error.createWorktree.pathExists"))
            return false
        }
    }

    let request = CreateWorktreeRequest(
        directoryPath: normalizedDirectoryPath,
        branchName: normalizedBranchName,
        createNewBranch: draft.createNewBranch
    )

    Task { @MainActor in
        do {
            if isRemote, let sshConfig = workspace.sshTarget {
                try await gitRepositoryService.createRemoteWorktree(rootPath: workspace.repositoryRoot, request: request, sshConfig: sshConfig)
                await refreshRemoteWorkspace(workspace)
            } else {
                try await gitRepositoryService.createWorktree(rootPath: workspace.repositoryRoot, request: request)
                await refreshWorkspace(workspace)
            }
            objectWillChange.send()
            if let worktree = workspace.worktrees.first(where: {
                if isRemote {
                    return $0.path == normalizedDirectoryPath
                } else {
                    return URL(fileURLWithPath: $0.path).standardizedFileURL.path == normalizedDirectoryPath
                }
            }) {
                activateWorktree(workspace: workspace, worktree: worktree, restartRunning: false, requestedAction: .none)
                if !isRemote {
                    runSetupScriptIfNeeded(in: workspace)
                }
            }
        } catch {
            presentError(title: localized("main.error.createWorktree.title"), message: error.localizedDescription)
        }
    }

    return true
}
```

**Step 3: Update `presentCreateWorktree`**

At line 1698, remove the `supportsRepositoryFeatures` guard (it now includes remote). Also pass `isRemote` info to the sheet request if needed. Since `CreateWorktreeSheetRequest` takes `repositoryRoot` and the sheet uses it for the directory picker, the sheet may need to know it's remote to disable the local folder picker. Add `isRemote` field:

Update `CreateWorktreeSheetRequest` in `Liney/Support/UIState.swift:77-82`:

```swift
struct CreateWorktreeSheetRequest: Identifiable {
    let id = UUID()
    let workspaceID: UUID
    let workspaceName: String
    let repositoryRoot: String
    let isRemote: Bool
}
```

Update `presentCreateWorktree` in `WorkspaceStore.swift`:

```swift
func presentCreateWorktree(for workspace: WorkspaceModel) {
    guard workspace.supportsRepositoryFeatures else { return }
    createWorktreeRequest = CreateWorktreeSheetRequest(
        workspaceID: workspace.id,
        workspaceName: workspace.name,
        repositoryRoot: workspace.repositoryRoot,
        isRemote: workspace.isRemote
    )
}
```

**Step 4: Update `CreateWorktreeSheet` for remote mode**

In `Liney/UI/Sheets/CreateWorktreeSheet.swift`, when `request.isRemote` is true:
- Hide the local folder picker button (NSOpenPanel won't work for remote paths)
- Show a text field for the remote directory path instead
- Default the directory path to `<repositoryRoot>/../<branchName>` (sibling directory pattern)

The exact UI changes depend on the current sheet layout — read the file and adapt. The key principle: remote mode replaces the folder picker with a plain text field.

**Step 5: Run tests**

Run: `xcodebuild -project Liney.xcodeproj -scheme Liney -destination 'platform=macOS' test 2>&1 | tail -30`
Expected: ALL PASS

**Step 6: Commit**

```bash
git add Liney/Services/Git/GitRepositoryService.swift Liney/App/WorkspaceStore.swift Liney/Support/UIState.swift Liney/UI/Sheets/CreateWorktreeSheet.swift
git commit -m "feat: add remote worktree creation via SSH"
```

---

### Task 5: Add remote worktree removal via SSH

**Files:**
- Modify: `Liney/Services/Git/GitRepositoryService.swift` (add `removeRemoteWorktree`)
- Modify: `Liney/App/WorkspaceStore.swift` (update `confirmPendingWorktreeRemoval`)

**Step 1: Add `removeRemoteWorktree` method to `GitRepositoryService`**

Add after `createRemoteWorktree`:

```swift
func removeRemoteWorktree(rootPath: String, path: String, force: Bool = false, sshConfig: SSHSessionConfiguration) async throws {
    var gitArgs = "git worktree remove"
    if force {
        gitArgs += " --force"
    }
    gitArgs += " '\(path)'"
    let script = "cd '\(rootPath)' && \(gitArgs)"

    var arguments = [
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=10",
    ]
    if let port = sshConfig.port {
        arguments.append(contentsOf: ["-p", "\(port)"])
    }
    if let identityFile = sshConfig.identityFilePath {
        arguments.append(contentsOf: ["-i", identityFile])
    }
    arguments.append(sshConfig.destination)
    arguments.append(script)

    let result = try await runner.run(
        executable: "/usr/bin/ssh",
        arguments: arguments,
        timeout: Self.remoteInspectTimeout
    )
    guard result.exitCode == 0 else {
        throw GitServiceError.commandFailed(
            result.stderr.nonEmptyOrFallback("Unable to remove remote worktree.")
        )
    }
}
```

**Step 2: Update `confirmPendingWorktreeRemoval` in WorkspaceStore**

At line 2272-2292, branch on whether workspace is remote:

```swift
func confirmPendingWorktreeRemoval(force: Bool = false) {
    guard let pendingWorktreeRemoval else { return }
    self.pendingWorktreeRemoval = nil
    guard let workspace = workspaces.first(where: { $0.id == pendingWorktreeRemoval.workspaceID }) else {
        return
    }

    Task { @MainActor in
        do {
            workspace.prepareForWorktreeRemoval(paths: pendingWorktreeRemoval.worktreePaths)
            for path in pendingWorktreeRemoval.worktreePaths {
                if workspace.isRemote, let sshConfig = workspace.sshTarget {
                    try await gitRepositoryService.removeRemoteWorktree(
                        rootPath: workspace.repositoryRoot, path: path, force: force, sshConfig: sshConfig
                    )
                } else {
                    try await gitRepositoryService.removeWorktree(rootPath: workspace.repositoryRoot, path: path, force: force)
                }
            }
            workspace.forgetWorktrees(paths: pendingWorktreeRemoval.worktreePaths)
            if workspace.isRemote {
                await refreshRemoteWorkspace(workspace)
            } else {
                await refreshWorkspace(workspace)
            }
        } catch {
            if workspace.isRemote {
                await refreshRemoteWorkspace(workspace)
            } else {
                await refreshWorkspace(workspace)
            }
            presentError(title: localized("main.error.removeWorktree.title"), message: error.localizedDescription)
        }
    }
}
```

**Step 3: Update `requestWorktreeRemoval` guards**

Lines 2228-2234 already use `supportsRepositoryFeatures` which now includes `.remoteServer`, so no change needed.

However, the `status(for:)` call at line 2248 may not work for remote worktrees yet. For remote worktrees without per-worktree status, use the workspace-level status as fallback. Check if `workspace.status(for:)` returns nil gracefully for unknown paths — if so, no change needed.

**Step 4: Run tests**

Run: `xcodebuild -project Liney.xcodeproj -scheme Liney -destination 'platform=macOS' test 2>&1 | tail -30`
Expected: ALL PASS

**Step 5: Commit**

```bash
git add Liney/Services/Git/GitRepositoryService.swift Liney/App/WorkspaceStore.swift
git commit -m "feat: add remote worktree removal via SSH"
```

---

### Task 6: Ensure remote worktrees appear in sidebar and have independent sessions

**Files:**
- Modify: `Liney/UI/Sidebar/WorkspaceSidebarView.swift` (verify worktree rendering)
- Modify: `Liney/App/WorkspaceStore.swift` (verify worktree switching for remote)

**Step 1: Verify sidebar already renders worktrees for remote workspaces**

Since `supportsRepositoryFeatures` now returns `true` for `.remoteServer`, the sidebar code at `WorkspaceSidebarView.swift:347-353` should automatically show worktree rows:

```swift
let visibleWorktrees = workspace.supportsRepositoryFeatures
    ? workspace.worktrees.filter { ... }
    : []
if workspace.supportsRepositoryFeatures, visibleWorktrees.count > 1 {
    // render worktree nodes
}
```

This should work without changes. Verify by reading the sidebar code.

**Step 2: Verify worktree switching sets correct SSH working directory**

When switching worktrees, `activateWorktree` should update `activeWorktreePath` to the remote worktree path. The SSH sessions should then use that path as the working directory.

Check `requestSwitchToWorktree` at line 2197-2199 — it calls `openWorktree`. Since the guard is `supportsRepositoryFeatures` which now includes remote, this should work.

The `RemoteSessionCoordinator` at line 39-56 constructs shell plans using `workspace.activeWorktreePath`, which will now be the remote worktree path. New panes opened after switching will SSH into the correct directory.

**Step 3: Verify per-worktree session state**

`WorkspaceModel.saveActiveWorktreeState()` and `loadActiveWorktreeState()` use `activeWorktreePath` as the key. Since remote worktree paths are unique strings (e.g., `/home/user/project-feature`), the per-worktree session state should work without changes.

The panes' `SessionBackendConfiguration` should default to `.ssh` for remote workspaces. Verify `WorkspaceSessionController` uses the workspace's SSH target when creating new panes.

**Step 4: Test manually if possible, or verify code paths**

Read the relevant code paths to confirm no blockers. The key checks:
1. `WorkspaceSidebarView` renders worktree rows when `supportsRepositoryFeatures` is true ✓
2. Worktree context menu (line 841) shows "Remove" for non-main worktrees ✓  
3. `requestSwitchToWorktree` works for remote workspaces ✓
4. New panes default to `.ssh` backend with correct working directory ✓

**Step 5: Commit any fixups**

```bash
git add -A
git commit -m "fix: ensure remote worktree sidebar display and session isolation"
```

---

### Task 7: Add per-worktree git status for remote workspaces

**Files:**
- Modify: `Liney/Services/Git/GitRepositoryService.swift` (extend SSH command for per-worktree status)
- Modify: `Liney/App/WorkspaceStore.swift` (populate `worktreeStatuses`)

**Step 1: Extend remote inspection to include per-worktree status**

The current remote inspection runs `git status` in the `cd <path>` directory (the active worktree). For full per-worktree status, we need to run `git status` in each worktree directory.

Option A: Run a single SSH command that iterates over worktrees and collects status per-directory. This is more efficient than multiple SSH calls.

Add a new method `inspectRemoteWorktreeStatuses` that takes the list of worktree paths and runs status in each:

```swift
func inspectRemoteWorktreeStatuses(
    worktreePaths: [String],
    sshConfig: SSHSessionConfiguration
) async throws -> [String: RemoteWorktreeStatus] {
    guard !worktreePaths.isEmpty else { return [:] }

    // Build a script that checks status in each worktree directory
    var scriptParts: [String] = []
    for path in worktreePaths {
        scriptParts.append("echo '__WT_PATH__'")
        scriptParts.append("echo '\(path)'")
        scriptParts.append("cd '\(path)' 2>/dev/null && echo '__WT_STATUS__' && git status --porcelain 2>/dev/null && echo '__WT_AHEAD_BEHIND__' && git rev-list --left-right --count HEAD...@{upstream} 2>/dev/null || true")
    }
    let script = scriptParts.joined(separator: " && ")

    var arguments = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10"]
    if let port = sshConfig.port { arguments.append(contentsOf: ["-p", "\(port)"]) }
    if let identityFile = sshConfig.identityFilePath { arguments.append(contentsOf: ["-i", identityFile]) }
    arguments.append(sshConfig.destination)
    arguments.append(script)

    let result = try await runner.run(executable: "/usr/bin/ssh", arguments: arguments, timeout: Self.remoteInspectTimeout)
    return Self.parseRemoteWorktreeStatuses(result.stdout)
}
```

Add the parser:

```swift
struct RemoteWorktreeStatus {
    var changedFileCount: Int
    var aheadCount: Int
    var behindCount: Int
}

nonisolated static func parseRemoteWorktreeStatuses(_ output: String) -> [String: RemoteWorktreeStatus] {
    var results: [String: RemoteWorktreeStatus] = [:]
    var currentPath = ""
    var changedFileCount = 0
    var aheadCount = 0
    var behindCount = 0
    var currentSection = ""

    for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed {
        case "__WT_PATH__":
            if !currentPath.isEmpty {
                results[currentPath] = RemoteWorktreeStatus(changedFileCount: changedFileCount, aheadCount: aheadCount, behindCount: behindCount)
            }
            currentPath = ""
            changedFileCount = 0
            aheadCount = 0
            behindCount = 0
            currentSection = "__WT_PATH__"
        case "__WT_STATUS__":
            currentSection = "__WT_STATUS__"
        case "__WT_AHEAD_BEHIND__":
            currentSection = "__WT_AHEAD_BEHIND__"
        default:
            switch currentSection {
            case "__WT_PATH__":
                if !trimmed.isEmpty { currentPath = trimmed }
            case "__WT_STATUS__":
                if !trimmed.isEmpty { changedFileCount += 1 }
            case "__WT_AHEAD_BEHIND__":
                if !trimmed.isEmpty {
                    let parts = trimmed.split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
                    if parts.count >= 2 { aheadCount = parts[0]; behindCount = parts[1] }
                }
            default: break
            }
        }
    }
    if !currentPath.isEmpty {
        results[currentPath] = RemoteWorktreeStatus(changedFileCount: changedFileCount, aheadCount: aheadCount, behindCount: behindCount)
    }
    return results
}
```

**Step 2: Update `refreshRemoteWorkspace` to populate `worktreeStatuses`**

After merging worktrees, if there are multiple worktrees, call `inspectRemoteWorktreeStatuses` and update `workspace.worktreeStatuses`:

```swift
// After worktree merge in refreshRemoteWorkspace...
if workspace.worktrees.count > 1 {
    do {
        let statuses = try await gitRepositoryService.inspectRemoteWorktreeStatuses(
            worktreePaths: workspace.worktrees.map(\.path),
            sshConfig: sshConfig
        )
        for (path, status) in statuses {
            workspace.worktreeStatuses[path] = RepositoryStatusSnapshot(
                hasUncommittedChanges: status.changedFileCount > 0,
                changedFileCount: status.changedFileCount,
                aheadCount: status.aheadCount,
                behindCount: status.behindCount,
                localBranches: [],
                remoteBranches: []
            )
        }
    } catch {
        // Per-worktree status is best-effort
    }
}
```

Note: Check the exact type of `worktreeStatuses` dictionary value — it may be `RepositoryStatusSnapshot` or a custom type. Read the code to confirm and adjust.

**Step 3: Write tests for `parseRemoteWorktreeStatuses`**

```swift
func testParseRemoteWorktreeStatuses() {
    let output = """
    __WT_PATH__
    /home/user/project
    __WT_STATUS__
    M  file1.txt
    __WT_AHEAD_BEHIND__
    1\t0
    __WT_PATH__
    /home/user/project-feature
    __WT_STATUS__
    __WT_AHEAD_BEHIND__
    0\t2
    """

    let statuses = GitRepositoryService.parseRemoteWorktreeStatuses(output)

    XCTAssertEqual(statuses.count, 2)
    XCTAssertEqual(statuses["/home/user/project"]?.changedFileCount, 1)
    XCTAssertEqual(statuses["/home/user/project"]?.aheadCount, 1)
    XCTAssertEqual(statuses["/home/user/project-feature"]?.changedFileCount, 0)
    XCTAssertEqual(statuses["/home/user/project-feature"]?.behindCount, 2)
}
```

**Step 4: Run tests**

Run: `xcodebuild -project Liney.xcodeproj -scheme Liney -destination 'platform=macOS' test 2>&1 | tail -30`
Expected: ALL PASS

**Step 5: Commit**

```bash
git add Liney/Services/Git/GitRepositoryService.swift Liney/App/WorkspaceStore.swift Tests/RemoteGitInspectionTests.swift
git commit -m "feat: add per-worktree git status for remote workspaces"
```

---

### Task 8: Final integration verification

**Files:**
- All modified files from previous tasks

**Step 1: Run full test suite**

```bash
xcodebuild -project Liney.xcodeproj -scheme Liney -destination 'platform=macOS' test 2>&1 | tail -40
```

Expected: ALL PASS

**Step 2: Build the app**

```bash
xcodebuild -project Liney.xcodeproj -scheme Liney -destination 'platform=macOS' build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED

**Step 3: Review all changes**

```bash
git log --oneline feat/remote-support --not main | head -20
git diff main...HEAD --stat
```

Verify the change set matches the plan.

**Step 4: Final commit (if any fixups needed)**

```bash
git add -A
git commit -m "fix: integration fixes for remote worktree support"
```
