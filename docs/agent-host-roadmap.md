# Agent Host Roadmap

Liney's main differentiation track: become the best macOS terminal workspace for
running multiple AI coding agents in parallel — Claude Code, Codex, Aider, and
whatever comes next. This roadmap captures the five pieces that make Liney an
"agent host" rather than just a terminal grid.

## Why this track

Today an agent in a pane has two ways to tell the user "I need you":

1. Print to stdout and hope the user is looking at that pane.
2. Fire a system desktop notification, which is noisy and loses pane context.

Both fail at scale. When a developer runs four or five agents across worktrees,
they end up tab-flipping to check who is blocked. cmux solved the symptom with
attention rings and a notifications panel; Liney already has the dynamic island
and a multi-worktree sidebar — combining them with a real IPC surface gets us
further than cmux because Liney owns the worktree model end-to-end.

## Items

### 1. Out-of-band notifications: OSC + `liney notify` CLI

**Status:** in progress (this PR).

- libghostty already parses OSC 9 and OSC 777 inside the terminal stream and
  emits `GHOSTTY_ACTION_DESKTOP_NOTIFICATION`. Liney now preserves the title,
  body, and originating pane all the way to the dynamic island.
- The Liney binary doubles as a CLI: `liney notify --title "Build done"` opens
  a Unix domain socket at
  `~/Library/Application Support/Liney/agent-notify.sock`, sends a JSON frame,
  and exits. The socket server runs in-process while the GUI is alive.
- `LINEY_PANE_ID` is injected into every PTY environment so an agent fired
  notification routes to the originating pane automatically.

### 2. Sidebar metadata for live sessions

**Status:** not started.

Make every workspace row in the sidebar carry agent-relevant context at a
glance:

- Active branch and PR number/state (already partially via
  `WorkspaceGitHubCoordinator`).
- Resolved working directory.
- Listening ports owned by the pane's process tree (`lsof`-based).
- Latest unread notification title.

### 3. Socket / IPC control API

**Status:** not started.

Generalize the `agent-notify.sock` server into a control plane:

- `liney open <repo> [--worktree <path>]`.
- `liney split [--axis vertical|horizontal]`.
- `liney send-keys <pane> <text>`.
- `liney session list`.

This is what turns Liney into an agent's environment, not just an agent's
viewer. cmux ships a similar surface; Liney's version should be scoped per
workspace and authenticated with the existing URL-scheme token model.

### 4. Agent-session resume tokens

**Status:** not started.

When a workspace is restored after relaunch, identify the agent CLI that was
running in each pane (Claude Code, Codex, Aider, etc.) and re-attach to its
on-disk session/conversation token rather than starting a fresh process.
Liney already restores tmux sessions and worktree layouts; restoring the
agent's *conversation* is the step cmux explicitly markets and the one users
actually feel.

Per-agent integration is small (a few JSON paths each); the generic part is
the registry and the launch hook.

### 5. Cross-worktree orchestration panel

**Status:** not started.

A new top-level surface (separate from the dynamic island) that aggregates,
across every open workspace and worktree:

- Each running agent: name, pane, status (`idle / running / waiting / error`).
- Recent notifications.
- Branch / PR state per worktree.

The user lands here, sees who is blocked, jumps directly to the right pane.
This becomes possible only after items 1 + 2 ship: the notification stream
populates the rows, the sidebar metadata fills the columns. cmux has the
pane-level attention ring; Liney's lever is the *worktree × agent matrix*.

## Sequencing

1, 2, 3, 4, 5 — strictly in order. Each item produces a primitive the next
one consumes. Skipping ahead (e.g., building the orchestration panel before
the IPC server) means re-doing the data plumbing later.

## Non-goals (for this track)

- Cross-platform (Linux/Windows): out of scope; macOS-first is the bet.
- In-app browser: large engineering investment, indirect agent-host value;
  reconsider after item 5 ships.
- Cloud VMs / remote runner: no plans; the SSH backend already covers the
  remote dev-machine case.
