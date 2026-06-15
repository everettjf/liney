# Agent Notifications

Liney surfaces notifications from anything running inside a pane — shells,
build tools, AI coding agents — through the dynamic island and the system
notification center. There are two delivery paths.

## OSC escape sequences (works automatically)

Anything in a pane that emits an OSC 9 or OSC 777 sequence is already picked
up. No setup required.

```sh
# OSC 9 (iTerm2 style) — title only
printf '\e]9;Build finished\a'

# OSC 777 (rxvt style) — title + body
printf '\e]777;notify;Build finished;All tests pass\a'
```

The body and title both flow through to the dynamic island. The originating
pane is recorded with the notification.

## `liney notify` CLI (out-of-band)

Use `liney notify` when an agent or script can't easily print to its parent
PTY — for example, a background job, a remote command over SSH, or a
process that buffers stdout. The CLI sends a JSON frame to the running
Liney app over a Unix domain socket; no PTY is required.

```sh
# Two positional arguments → title, body
liney notify "Claude is waiting" "Choose an option"

# Flag form
liney notify --title "Build done" --body "All tests pass"

# Short flags
liney notify -t "Codex" -m "Needs your input" -a "Codex"

# From inside a pane, $LINEY_PANE_ID auto-routes to that pane
liney notify --title "Tests passing" --body "🎉"
```

### Options

| Flag | Meaning |
|---|---|
| `-t, --title <text>` | Notification title (required if no positional given) |
| `-b, --body <text>`  | Notification body (alias `-m`, `--message`) |
| `-p, --pane <uuid>`  | Originating pane (defaults to `$LINEY_PANE_ID`) |
| `-w, --workspace <uuid>` | Originating workspace |
| `-a, --agent <name>` | Agent display name (e.g. `Claude`, `Codex`) |
| `-V, --version`      | Print Liney version and exit |
| `-h, --help`         | Show help and exit |

### Exit codes

| Code | Meaning |
|---|---|
| `0`  | Notification accepted by the app |
| `64` | Usage error (missing arguments, unknown flag) |
| `69` | Liney is not running |
| `74` | I/O error talking to the socket |

### Routing rules

When a request arrives, Liney resolves the target workspace in this order:

1. Explicit `--workspace <uuid>` if provided.
2. The workspace whose currently-active session controller owns the
   `--pane <uuid>` (or `$LINEY_PANE_ID`) the request was tagged with.
3. The currently-selected workspace.

The notification is then posted to the dynamic island for that workspace
with the pane recorded as `terminalTag` so click-through can navigate
back to the originating pane.

## `liney status` CLI (attention state)

A notification is a one-shot event ("build done"). A *status* is a persistent
state for the pane — `running`, `waiting`, `done`, or `error` — that Liney
keeps until the agent reports a new one. This is what lets you glance at the
dynamic island (or `liney session list`) and see *which* agent is blocked,
the way cmux's attention ring does.

Like `liney notify`, it is a self-report: no token is required, and the pane
defaults to `$LINEY_PANE_ID`, so from inside an agent hook you can just run:

```sh
# Agent is now blocked on the user
liney status waiting --title "Approve running the migration?"

# Agent finished its task
liney status done

# Agent hit an error
liney status error --title "build failed"
```

The state token is permissive — these all map to the four canonical states:

| Canonical | Accepted synonyms |
|---|---|
| `running` | `busy`, `working`, `start`, `started` |
| `waiting` | `wait`, `blocked`, `input`, `needs-input` |
| `done`    | `complete`, `completed`, `finished`, `success`, `ok` |
| `error`   | `failed`, `fail` |

A `waiting`, `done`, or `error` report opens the dynamic island to draw
attention; a `running` report updates the row silently so progress chatter
doesn't keep popping the panel.

### Options

| Flag | Meaning |
|---|---|
| `<state>` (positional) | One of the states/synonyms above (required) |
| `--pane <uuid>`  | Originating pane (defaults to `$LINEY_PANE_ID`) |
| `--title <text>` | Optional label shown on the island row |
| `--agent <name>` | Agent display name (e.g. `Claude`, `Codex`) |
| `-h, --help`     | Show help and exit |

The reported state shows up in `liney session list` per pane (`<waiting>` in
the plain output, a `status` field in `--json`), so an external orchestrator
can poll for blocked agents.

## Driving and reading other panes (`read` / `agents`)

The control socket also lets an agent inspect and coordinate its **sibling**
agents — the loop that makes a Liney workspace self-driving. These commands are
token-gated (see "Wire format"); export `LINEY_CONTROL_TOKEN` once.

```sh
# Which panes currently host an agent, and what state are they in?
liney agents --json    # [{pane,type,name,status,reported,cwd,branch,focused}, ...]

# Read a sibling pane's rendered terminal text (last 80 lines)
liney read --pane <uuid> --last 80 --json | jq -r '.text'

# Wait until the pane's TUI stops streaming before reading
liney read --pane <uuid> --last 200 --wait-stable --json | jq -r '.text'

# Then act on it
liney send-keys <uuid> 'npm test\n'
```

`liney agents` combines two signals: passive detection from the pane's process
tree (so an agent that never calls `liney status` is still listed, with
`reported: false`) and the authoritative `liney status` self-reports
(`reported: true`). `liney read` pulls the text straight from the Ghostty
surface buffer; `--scrollback` includes history beyond the visible viewport.

The bundled **`liney-cli` skill** (`skills/liney-cli/SKILL.md`) packages this
loop so a coding agent knows when and how to use it.

## Environment variables Liney injects

Inside every pane Liney spawns, these are set:

| Variable | Value |
|---|---|
| `LINEY_PANE_ID` | UUID of the owning pane — used by `liney notify` for routing |
| `LINEY_SESSION_ID` | UUID of the current process-launch attempt — used by Liney's process-reaper |
| `TERM_PROGRAM` | `Liney` |
| `TERM_PROGRAM_VERSION` | The current Liney version |

`LINEY_PANE_ID` is the one to use from agents and scripts.

## Installing the CLI shim

The Liney app binary is itself the CLI; the executable inside the .app bundle
already understands `notify` as a subcommand. The simplest way to expose it
on `$PATH`:

```sh
sudo ln -sf /Applications/Liney.app/Contents/MacOS/Liney /usr/local/bin/liney
```

After that, `liney notify ...` works from any shell.

## Wire format (for tooling)

The CLI is a thin client over a JSON-line protocol. If you'd rather skip the
binary and write directly to the socket, send a single newline-terminated
JSON object to `~/Library/Application Support/Liney/agent-notify.sock`:

```json
{"v":1,"title":"Build done","body":"All tests pass","pane":"<uuid>","agent":"Claude"}
```

Fields: `v` (int, currently `1`), `title` (string, optional if `body` set),
`body`, `pane`, `workspace`, `agent` (all optional strings). Unknown fields
are ignored — the protocol is forward-compatible.
