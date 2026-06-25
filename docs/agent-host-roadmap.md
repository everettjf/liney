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

**Status:** partially shipped.

Make every workspace row in the sidebar carry agent-relevant context at a
glance:

- Active branch and PR number/state (already partially via
  `WorkspaceGitHubCoordinator`).
- Resolved working directory.
- Listening ports owned by the pane's process tree (`lsof`-based). **Shipped**
  — `ListeningPortInspector` + the `:3000` sidebar badge.
- Latest unread notification title.

### 3. Socket / IPC control API

**Status:** shipped.

The `agent-notify.sock` server is now a general control plane
(`LineyControlProtocol` / `LineyControlDispatcher`):

- `liney open <repo> [--worktree <path>]`.
- `liney split [--axis vertical|horizontal]`.
- `liney send-keys <pane> <text>`.
- `liney session list`.
- `liney status <running|waiting|done|error>` — the agent attention signal.
  Unauthenticated and fire-and-forget like `notify` (a pane reporting about
  itself), it sets a per-pane state surfaced in the dynamic island and
  `session list`. This is the missing piece versus cmux's attention ring:
  Liney already had the `IslandItemStatus.waitingForInput` model but no IPC
  path for an agent to set it.
- `liney read [--pane] [--last N] [--scrollback] [--wait-stable]` — read a
  pane's rendered terminal text via `ghostty_surface_read_text`. `--wait-stable`
  polls (client-side) until the screen stops changing, so an agent can read a
  sibling's TUI output without catching a half-painted frame.
- `liney agents` — the roster of panes that currently host an agent, detected
  passively from the process tree (`AgentProcessDetector`, argv-based so
  node-wrapped CLIs like Claude Code are caught) and merged with the
  `liney status` self-reports. This is what lets a coding agent inspect and
  coordinate its sibling agents (the Prowl `prowl agents` / self-driving model).

Mutating actions (`open` / `split` / `send-keys`) are authenticated with the
existing URL-scheme token model — and Liney injects that token into every pane
as `LINEY_CONTROL_TOKEN` so an in-pane agent can use them without manual setup.
The self-reports (`notify` / `status`) and the read-only inspection commands
(`session list` / `read` / `agents`) require no token: they mutate nothing and
the control socket is already owner-only.

### 4. Agent-session resume tokens

**Status:** shipped.

When a workspace is restored after relaunch, an agent pane re-attaches to its
most recent conversation for that working directory instead of starting cold —
the step cmux explicitly markets and the one users actually feel.

Rather than capture each agent's internal session id (fragile, per-agent JSON
paths), Liney leans on the agents' own cwd-scoped "continue last" conventions,
which gives the same result with no bookkeeping:

- claude → `--continue`
- codex → `resume --last`
- aider → `--restore-chat-history`

Implementation:

- `AgentResumeRegistry` (the generic registry) rewrites an agent launch's
  arguments to resume. Conservative: only verified agents, idempotent (won't
  double-add), unknown/already-resuming launches pass through untouched.
- The launch hook fires only on a true restore-after-relaunch: `PaneSnapshot`
  carries a transient `restoredFromDisk` flag set solely when decoded from the
  on-disk workspace state (fresh panes and in-memory worktree switches leave it
  false), threaded through `ShellSession` into the `.agent` launch builder.

Default-on; a user toggle is the obvious follow-up if needed.

### 5. Cross-worktree orchestration panel

**Status:** shipped.

A top-level surface (separate from the dynamic island), opened from **View →
Agents Panel** (`⌘⇧A`), that aggregates across every open workspace:

- Each running agent: name, type, pane, status (`running / waiting / done /
  error`), attention-first so a blocked agent floats to the top.
- Branch / PR state and listening ports per worktree.
- Recent notifications.

Implemented as `AgentOrchestrationStore` (aggregation, reusing the
`AgentProcessDetector` + `AgentStatusStore` signals behind `liney agents`),
`AgentOrchestrationView`, and `AgentOrchestrationWindowManager` (modeled on
`HistoryWindowManager`, with a 2.5s refresh while open). Clicking a row reveals
the backing pane via `LineyDesktopApplication.revealAgentPane`. Pane close now
evicts the pane's `AgentStatusStore` entry so rows don't go stale.

The user lands here, sees who is blocked, jumps directly to the right pane.
This becomes possible only after items 1 + 2 ship: the notification stream
populates the rows, the sidebar metadata fills the columns. cmux has the
pane-level attention ring; Liney's lever is the *worktree × agent matrix*.

The per-agent status column already has its data source: `liney status`
records state into `AgentStatusStore` keyed by pane (item 3). What remains is
the aggregating surface itself and wiring pane-close eviction.

### 6. Review → merge loop across worktrees

**Status:** in progress.

Items 1–5 solved *running* many agents; the remaining gap is the part no
competitor (cmux, ghostree) has made smooth: after N agents finish, how do I
quickly review → pick → merge their output? This is now Liney's primary moat —
"true terminal + worktree" alone is no longer a differentiator.

First slice (this work): apply one worktree's changes onto another, straight
from the diff window.

- `GitRepositoryService.workingTreePatch(for:)` builds a single unified patch of
  a worktree's full working-tree state vs HEAD — tracked *and* untracked files —
  by staging into a throwaway `GIT_INDEX_FILE` so the real index is never
  touched.
- `precheckApplyPatch(_:to:)` dry-runs it with `git apply --check` so conflicts
  are surfaced *before* anything is written.
- `applyPatch(_:to:threeWay:)` applies it, with an opt-in `--3way` fallback that
  leaves conflict markers when the patch doesn't apply cleanly.
- The diff window gains an "apply to another worktree" menu (target = sibling
  worktrees) and a confirmation sheet showing the precheck verdict.
- File-level cherry-pick: the confirmation sheet lists every changed file with a
  checkbox (all selected by default); `workingTreePatch(for:paths:)` scopes the
  patch to the chosen subset and the precheck re-runs as the selection changes,
  so you can pick exactly which files merge into the target.

Second slice (shipped): the rest of the loop.

- **Per-hunk cherry-pick.** `UnifiedPatch` parses the patch into file sections
  and hunks; the sheet shows a file → hunk tree of checkboxes and reassembles
  only the selected hunks (`UnifiedPatch.reassemble`). Selection drives the live
  precheck, so you cherry-pick at sub-file granularity.
- **A/B compare.** `worktreeContentTree(for:)` snapshots each worktree's full
  content (incl. uncommitted/untracked) into a git tree via a throwaway index,
  and the diff window compares the two trees (`rectangle.split.2x1` toolbar menu
  → a compare banner; "Exit Compare" returns to changes-vs-HEAD).
- **Interactive conflict resolution.** `applyPatch(…, threeWay:)` now reports
  conflicts instead of throwing; the sheet lists each conflicted file with
  "Use incoming" / "Keep target" (`git checkout --theirs/--ours` + stage), or
  leave the markers to edit in the worktree. Because `git apply --3way` refuses
  a dirty target ("does not match index"), the apply stages the target worktree
  (`git add -A`) first so the merge's "ours" side reflects its current state.

Possible further work: inline (within-document) conflict editing and applying
across repositories rather than only sibling worktrees.

## Sequencing

1, 2, 3, 4, 5 — strictly in order. Each item produces a primitive the next
one consumes. Skipping ahead (e.g., building the orchestration panel before
the IPC server) means re-doing the data plumbing later. Item 6 builds on the
worktree model and the diff window that items 1–5 established.

## Non-goals (for this track)

- Cross-platform (Linux/Windows): out of scope; macOS-first is the bet.
- In-app browser: large engineering investment, indirect agent-host value;
  reconsider after item 5 ships.
- Cloud VMs / remote runner: no plans; the SSH backend already covers the
  remote dev-machine case.
