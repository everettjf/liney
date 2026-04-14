# Remote Server Support Design

Date: 2026-04-10

## Overview

Add comprehensive remote server support to Liney, learning from treemux's implementation. This includes SSH config parsing, connection testing, SFTP file browsing, remote directory browser, tmux session detection and automatic restoration, remote git inspection, periodic refresh, and a dedicated remote workspace creation flow.

## Decisions

| Decision | Choice |
|----------|--------|
| Scope | Full implementation of all remote features |
| Data model strategy | Reuse and extend existing Liney models |
| SFTP password auth | Introduce Citadel library as fallback |
| Sidebar display | Mixed with local workspaces, distinguished by badge |
| Remote workspace creation | New dedicated Sheet (separate from existing SSH pane Sheet) |
| Tmux behavior | Fully automatic: detect, persist, restore |
| Implementation approach | Layered incremental (services → models → terminal → UI) |

## Architecture: Layered Incremental

```
Layer 4: UI
  └─ CreateRemoteWorkspaceSheet, RemoteDirectoryBrowser, sidebar badge

Layer 3: Terminal Integration
  └─ ShellSession tmux detection, SessionBackendLaunch tmux/SSH
  └─ WorkspaceSessionController restore logic
  └─ Remote git inspection, periodic refresh

Layer 2: Data Model Extensions
  └─ TmuxAttachConfiguration, PaneSnapshot.detectedTmuxSession
  └─ WorkspaceKind.remoteServer, WorkspaceRecord.sshTarget

Layer 1: Foundation Services
  └─ SSHConfigParser, SSHConfigService
  └─ TmuxService
  └─ SFTPService (+ Citadel)
```

## Layer 1: Foundation Services

### 1.1 SSH Config Parsing

New files:
- `Liney/Services/SSH/SSHConfigParser.swift`
- `Liney/Services/SSH/SSHConfigService.swift`

**SSHConfigParser**:
- Parse `~/.ssh/config` extracting Host, HostName, Port, User, IdentityFile
- Filter wildcard patterns (`*`, `?`)
- Return structured SSH target list

**SSHConfigService**:
- Load targets via SSHConfigParser
- `testConnection(_:)` using `/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=5`
- Return status enum: `.connected`, `.authRequired`, `.unreachable(Error)`

### 1.2 Tmux Service

New file: `Liney/Services/Tmux/TmuxService.swift`

Model:
```swift
struct TmuxSessionInfo: Codable, Identifiable {
    var id: String { name }
    let name: String
    let windowCount: Int
    let isAttached: Bool
    let createdAt: Date?
}
```

Methods:
- `listLocalSessions()` — local `tmux list-sessions -F`
- `listRemoteSessions(_ target:)` — via SSH
- `isSessionAlive(name:)` — check session exists
- `attachCommand(for:)` / `remoteAttachCommand(for:via:)` — build attach commands

### 1.3 SFTP Service

New files:
- `Liney/Services/SFTP/SFTPService.swift`
- `Liney/Services/SFTP/SFTPDirectoryEntry.swift`

**Primary path**: System `/usr/bin/ssh` with `ls -1pa` for directory listing (key-based auth).

**Fallback**: Citadel library for password-based SSH authentication. Citadel is introduced as a dependency (SPM or xcframework).

Methods:
- `connect(target:)` — key-based auth via system SSH
- `connectWithPassword(target:password:)` — Citadel password auth
- `listDirectories(at:)` — list subdirectories (hidden files filtered)
- `homeDirectory()` — get remote user's home path

Errors: `.notConnected`, `.authenticationFailed`, `.keyFileNotFound`, `.commandFailed`

## Layer 2: Data Model Extensions

### 2.1 SessionBackendConfiguration — new tmuxAttach case

```swift
// New backend kind
enum SessionBackendKind: String, Codable, CaseIterable {
    case localShell, ssh, agent
    case tmuxAttach  // NEW
}

// New configuration
struct TmuxAttachConfiguration: Codable, Hashable {
    var sessionName: String
    var windowIndex: Int?
    var isRemote: Bool
    var sshTarget: SSHSessionConfiguration?  // Reuse existing model
}
```

Add `.tmuxAttach(TmuxAttachConfiguration)` case to `SessionBackendConfiguration` with corresponding Codable support.

### 2.2 PaneSnapshot — new detectedTmuxSession field

```swift
struct PaneSnapshot: Codable, Hashable, Identifiable {
    // ... existing fields ...
    var detectedTmuxSession: String?  // NEW: auto-detected tmux session name
}
```

### 2.3 WorkspaceKind / WorkspaceRecord — remote workspace support

```swift
enum WorkspaceKind: String, Codable {
    case repository, localTerminal
    case remoteServer  // NEW
}

struct WorkspaceRecord {
    // ... existing fields ...
    var sshTarget: SSHSessionConfiguration?  // NEW: SSH config for remote workspaces
}
```

`WorkspaceModel` gains `@Published var sshTarget: SSHSessionConfiguration?` and computed `var isRemote: Bool`.

### 2.4 Persistence compatibility

All new fields use `decodeIfPresent` with `nil` defaults for backward compatibility with existing workspace-state.json files.

## Layer 3: Terminal Integration

### 3.1 ShellSession — tmux detection

Add `detectTmux(fromTitle:)` to ShellSession, called from `onTitleChange`.

Three detection patterns:
1. `[session-name] ...` — tmux status bar format
2. `tmux new -s xxx` — preexec command title
3. `dev:0:bash - "hostname"` — tmux set-titles format (`#S:#I:#W - "#T"`)

For bare `tmux` (no session name parsed), resolve via process tree: find tmux client PID among shell descendants, then query `tmux list-clients` for actual session name.

Result stored in `ShellSession.detectedTmuxSession: String?`.

### 3.2 SessionBackendLaunch — tmuxAttach launch config

Add `.tmuxAttach` case to `makeLaunchConfiguration`:

- **Local**: `/bin/zsh --login -c "exec tmux attach-session -t <name>"`
- **Remote**: `/usr/bin/ssh -t [user@]host 'tmux attach-session -t <name>'`

Enhance existing SSH launch: inject `tmux set-option -g set-titles on 2>/dev/null;` prefix in remote commands so tmux title changes propagate for detection.

### 3.3 WorkspaceSessionController — tmux restore logic

When restoring panes from PaneSnapshot, if `detectedTmuxSession` is non-nil:
- `.localShell` backend → replace with `.tmuxAttach(isRemote: false)`
- `.ssh` backend → replace with `.tmuxAttach(isRemote: true, sshTarget: ...)`
- Other backends → no change

### 3.4 Remote git inspection

Extend `GitRepositoryService`:
- `inspectRepository(remotePath:sshTarget:)` — run combined git commands via SSH
- Parse remote branch, HEAD, worktree list, status, ahead/behind counts

### 3.5 Periodic remote refresh

Add to `WorkspaceStore`:
- 30-second Timer polling all non-archived remote workspaces' git state
- 5-second tolerance for power efficiency
- Immediate refresh on `NSWindow.didBecomeKeyNotification`
- Reentry guard (`isRefreshingRemotes`) to prevent concurrent refreshes
- Disabled for local workspaces (they use file system watchers)

## Layer 4: UI

### 4.1 CreateRemoteWorkspaceSheet (new)

New file: `Liney/UI/Sheets/CreateRemoteWorkspaceSheet.swift`

- **SSH target picker**: auto-load from `~/.ssh/config` via SSHConfigService
- **Connection status indicator**: auto-test on target selection (green/yellow/red)
- **Remote path**: text field + "Browse..." button opening RemoteDirectoryBrowser
- **Workspace name**: defaults to remote directory name, editable
- **Create button**: creates `.remoteServer` workspace with SSH target

### 4.2 RemoteDirectoryBrowser (new)

New files:
- `Liney/UI/Sheets/RemoteDirectoryBrowser.swift`
- `Liney/UI/Sheets/RemoteDirectoryBrowserViewModel.swift`

- Tree view of remote directories with lazy-loaded children
- Connection status display: "Connecting...", "Password required", error
- Password prompt on key auth failure (Citadel fallback)
- Path bar for direct navigation
- Returns selected path on confirmation

### 4.3 Sidebar — remote workspace badge

In `WorkspaceRowContent` (workspace row only, not worktree rows), add:

```swift
if workspace.isRemote {
    SidebarInfoBadge(text: localized("sidebar.badge.remote"), tone: .accent)
}
```

Localization in `L10n.swift`:
- English: `"sidebar.badge.remote": "remote"`
- Chinese: `"sidebar.badge.remote": "远程"`

Uses the existing `SidebarInfoBadge` component with `.accent` tone (blue), consistent with existing `flow` badge style.

### 4.4 Entry points

- **Sidebar**: "+" button or menu → "Add Remote Workspace"
- **Command Palette**: new `.createRemoteWorkspace` command
- **Menu bar**: File → "New Remote Workspace..."

## Dependencies

- **Citadel** (Swift SSH2 client): for SFTP password authentication fallback
- All other features use system `/usr/bin/ssh`

## Testing strategy

Each layer should have unit tests:
- Layer 1: SSH config parsing, tmux output parsing, SFTP directory listing (mockable)
- Layer 2: Codable round-trip tests for new/extended models, backward compatibility
- Layer 3: Tmux title detection patterns, backend launch command construction, restore logic
- Layer 4: Manual UI testing for sheets and sidebar display

## Reference

- Treemux source: `/Users/yanu/Documents/code/Terminal/treemux`
- Key treemux files studied: `TmuxService.swift`, `SessionBackend.swift`, `SFTPService.swift`, `SSHConfigParser.swift`, `WorkspaceSessionController.swift`, `ShellSession.swift`
