<!--
  terminal-architecture.md
  Liney

  Author: everettjf
-->

# Terminal Architecture

Liney keeps terminal code split between a small set of abstractions and a dedicated Ghostty adapter layer. The goal is to let higher-level session code talk to a stable interface while the `libghostty` bridge stays isolated.

## Directory Layout

```text
Liney/Services/Terminal/
├─ Ghostty/
│  ├─ LineyGhosttyBootstrap.swift
│  ├─ LineyGhosttyClipboardSupport.swift
│  ├─ LineyGhosttyController.swift
│  ├─ LineyGhosttyInputSupport.swift
│  └─ LineyGhosttyRuntime.swift
├─ SessionBackendLaunch.swift
├─ ShellSession.swift
├─ TerminalSurface.swift
└─ WorkspaceSessionController.swift
```

## Responsibilities

### `TerminalSurface.swift`

Defines the app-facing terminal protocols:

- `TerminalSurfaceController`
- `ManagedTerminalSessionSurfaceController`
- `TerminalSurfaceFactory`

Higher layers should depend on these protocols first, not on Ghostty concrete types.

### `ShellSession.swift`

Owns the lifecycle of a single terminal session:

- launch configuration
- working-directory tracking
- title updates
- process exit handling
- focus and search commands

This layer should not know about Ghostty callbacks beyond the controller protocol.

### `WorkspaceSessionController.swift`

Coordinates multiple sessions for a workspace and feeds pane-level UI state.

### `Ghostty/LineyGhosttyRuntime.swift`

Owns the shared `libghostty` app/runtime instance, callback wiring, and clipboard callback entry points.

### `Ghostty/LineyGhosttyController.swift`

Bridges one managed terminal surface to AppKit:

- creates and destroys surfaces
- forwards Ghostty actions to workspace commands
- manages search/read-only state snapshots
- handles input, IME, selection, cursor, and secure-input behaviors

### `Ghostty/LineyGhosttyInputSupport.swift`

Contains pure keyboard and IME helper logic. This file is intentionally kept light on object state so its behavior can be unit tested directly.

### `Ghostty/LineyGhosttyClipboardSupport.swift`

Normalizes clipboard read/write helpers and payload typing used by the runtime and controller.

### `Ghostty/LineyGhosttyBootstrap.swift`

Performs one-time `libghostty` global initialization before the app starts driving any terminal surface.

## Design Rules

- Keep `libghostty` specifics inside `Liney/Services/Terminal/Ghostty/`.
- Prefer pure helper functions for modifier translation, text routing, and selection rules when possible.
- Let `ShellSession` observe controller callbacks rather than owning Ghostty state directly.
- Avoid adding new terminal-engine abstractions unless the app genuinely supports another engine again.
- Do not modify `Liney/Vendor/` unless the change explicitly requires a new Ghostty binary or header surface.

## When To Add Tests

Add unit coverage when changing:

- key routing or modifier translation
- IME marked-text behavior
- clipboard permission flows
- workspace-action dispatch from Ghostty callbacks
- session lifecycle transitions in `ShellSession`

For UI-heavy terminal changes, pair unit tests with a small manual smoke test note covering focus, typing, split operations, and search if those behaviors were touched.

## Optional history snapshots

Settings → Terminal → **Restore terminal history after restart** is global and
opt-in. The default remains off; workspace layout and working-directory
restoration do not require it. `restoreTerminalHistory` decodes as `false` for
older settings files.

`TerminalHistoryCoordinator` tracks live sessions weakly and captures changed
rendered text about every 10 seconds. `WorkspaceStore.flushPendingPersistence()`
flushes a final snapshot on normal app exit. `TerminalHistoryPersistence` writes
one atomic UTF-8 snapshot per pane ID under the state directory's
`terminal-history/` folder. It keeps the newest complete characters within 2 MiB
per pane and evicts the oldest files above 100 MiB globally. The directory is
owner-only (0700), and snapshots are owner-readable/writable (0600).

After relaunch, a pane with a saved snapshot offers **Previous session history →
View History** in a read-only, selectable view. The existing Ghostty bridge
exposes rendered text reads but no scrollback import operation. Saved text is
never passed to `sendText` or executed, and no running process is restored.
Force-killing the app may lose output since the last periodic snapshot.

Explicitly closing a pane/tab or removing its workspace discards its snapshots.
Disabling the setting removes all snapshots and clears loaded history. Queued
writes and deletes are serialized so a pending save cannot resurrect deleted
history. Normal app exit retains the latest snapshots for the next launch.
