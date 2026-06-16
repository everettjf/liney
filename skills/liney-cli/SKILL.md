---
name: liney-cli
description: >-
  Use the Liney CLI (`liney`) to inspect or control a running Liney terminal
  workspace and the agent sessions it hosts. Liney runs several coding agents in
  parallel, each in its own pane/tab/worktree, so reach for this whenever the
  user wants to act on a pane other than the current one — check on, coordinate,
  read from, or send text/keys to another pane, tab, worktree, or sibling agent.
  Covers framings that never say "liney": "what is the agent in my other window
  doing", "are my side-by-side agents still working or waiting?", "tell the
  agent in my left split to rerun the tests", "read the build pane's output",
  "which of my agents is blocked?". Not for ordinary editing or building inside
  the Liney source repo, and not for questions about Liney's settings or
  keybindings — only when the task is to actually drive panes in the live app.
---

# Liney CLI

Use `liney` only when the task is to inspect or control the running Liney GUI
app: list/read panes, check sibling agents, send text/keys, or report your own
status. Do not use it merely because the current shell is inside the Liney repo.

## Auth

Most of the time you need to do nothing. When **Settings → URL Scheme** is
enabled, Liney injects `LINEY_CONTROL_TOKEN` into every pane's environment, so
an agent running in a Liney pane can call the mutating commands (`open`,
`split`, `send-keys`) with no setup.

- **No token at all:** `session list`, `read`, `agents` (read-only inspection)
  and `notify`, `status` (self-reports). These always work.
- **Token (auto-injected, or `export LINEY_CONTROL_TOKEN=<token>` if you run
  from outside a Liney pane):** `open`, `split`, `send-keys`.

## Identify a pane before acting

Always resolve a concrete pane UUID before `read` or `send-keys`.

```bash
liney session list --json | jq -r '.[].pane'   # all panes (id, cwd, branch, ports, status)
liney agents --json       | jq -r '.[].pane'   # only panes with a detected/reported agent
```

`liney agents` is the right starting point for "which agents are blocked /
working / done?"; `liney session list` is the full pane inventory including
plain shells.

If your own session was launched from a Liney pane, the focused pane is often
you. Treat focused pane IDs as something to identify and avoid unless you mean
to operate on yourself.

```bash
self_pane="$(liney agents --json | jq -r '.[] | select(.focused) | .pane')"
```

## Read another pane

```bash
liney read --pane "$pane" --last 80 --json | jq -r '.text'
liney read --pane "$pane" --scrollback --json | jq -r '.text'     # include history
liney read --pane "$pane" --last 200 --wait-stable --json | jq -r '.text'
```

`--wait-stable` re-reads until the screen stops changing — use it when an
agent's TUI may still be streaming a response so you don't read a half-painted
frame.

## Drive another pane

```bash
liney send-keys "$pane" 'npm test\n'          # text, trailing \n submits
liney send-keys "$pane" $'\x03'               # Ctrl-C
liney open ~/proj --worktree ~/proj/.wt/x     # open a repo / switch worktree
liney split --axis vertical --pane "$pane"    # split a pane
```

Use this only for a pane you have positively identified. If `$pane` is your own
pane, the keys land in your current session.

## Report your own status (no token)

When *you* are the agent in a Liney pane, tell Liney how you're doing so the
user sees it in the dynamic island and `liney agents`:

```bash
liney status waiting --title "Approve running the migration?"
liney status done
liney status error --title "build failed"
```

## A typical "check on a blocked agent" loop

```bash
self_pane="$(liney agents --json | jq -r '.[] | select(.focused) | .pane')"
pane="$(liney agents --json | jq -r --arg me "$self_pane" '
  .[] | select(.status == "waiting" and .pane != $me) | .pane' | head -n1)"
test -n "$pane" && liney read --pane "$pane" --last 120 --wait-stable --json | jq -r '.text'
```

## Parsing JSON output

- `session list --json` → array of `{ workspace, workspaceName, pane, cwd, branch, ports, status }`.
- `agents --json` → array of `{ workspace, workspaceName, pane, type, name, status, reported, cwd, branch, focused }`.
  - `status` is `running | waiting | done | error`.
  - `reported` is `true` when `status` came from a `liney status` self-report,
    `false` when it was passively detected from the pane's process tree.
- `read --json` → `{ ok, text, lineCount }`; the terminal text is `.text`.

When JSON is stored in a shell variable, use `printf '%s\n' "$json" | jq ...`,
not `echo "$json" | jq` — zsh can turn JSON escape sequences such as ``
back into raw control characters.

## Installing the CLI shim

The Liney app binary is itself the CLI:

```bash
sudo ln -sf /Applications/Liney.app/Contents/MacOS/Liney /usr/local/bin/liney
```

## Exit codes

`0` ok · `64` usage · `69` Liney not running · `74` I/O error · `77` auth
required (missing/invalid token).
