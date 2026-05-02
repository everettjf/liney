# Lifecycle Hooks

Liney can run user-defined commands at four lifecycle points:

| Hook name           | When it fires                              | Frequency                     |
| ------------------- | ------------------------------------------ | ----------------------------- |
| `app.on_launch`     | Once after the app finishes loading        | Once per app launch           |
| `app.on_quit`       | When the app is quitting (best effort)     | Once per app quit             |
| `session.on_start`  | When a terminal session is started         | Per session                   |
| `session.on_exit`   | When a terminal session's process exits    | Per session                   |

Hooks are user-controlled and disabled by default. Turn them on in **Settings → App → Hooks**.

## Configuration file

Lives at `~/.liney/hooks.json` (or `~/.liney-debug/hooks.json` for the debug build).

```json
{
  "version": 1,
  "hooks": {
    "app.on_launch": [
      { "enabled": true, "sync": false, "command": "echo \"liney up at $(date)\" >> ~/.liney/hook.log" }
    ],
    "app.on_quit": [],
    "session.on_start": [
      { "enabled": true, "sync": false, "command": "claude --resume" },
      { "enabled": true, "sync": true, "command": "load-project-env", "timeoutSeconds": 5 }
    ],
    "session.on_exit": []
  }
}
```

Per-command fields:

| Field            | Type     | Default                       | Description                                                    |
| ---------------- | -------- | ----------------------------- | -------------------------------------------------------------- |
| `enabled`        | bool     | `true`                        | Skip the command without removing it.                          |
| `sync`           | bool     | `false`                       | If `true`, the caller blocks until the command completes.      |
| `command`        | string   | (required)                    | Passed to `/bin/sh -c`.                                        |
| `timeoutSeconds` | number   | `5` (sync), `30` (async)      | Per-command kill switch. Override when you know what you need. |

- Each hook point holds an array, so you can chain multiple commands. They run in declaration order; sync ones inline, async ones on a background queue.
- The fastest way to create the file is **Settings → Hooks → Open hooks.json** — Liney will scaffold it with disabled examples.

### Sync vs async

| Mode    | When to use                                                                            |
| ------- | -------------------------------------------------------------------------------------- |
| `false` (async, default) | Side effect doesn't gate anything (notifications, logging, kicking off background work). The hook returns immediately and the command runs in the background. |
| `true` (sync)            | The hook's outcome must be visible before downstream work proceeds (env injection, resource locks, schema migrations). The caller blocks for up to `timeoutSeconds`. |

Sync hooks block the caller's thread. For `session.on_start` that means a slow sync hook delays the terminal becoming ready; for `app.on_launch` it delays the UI. Use it when you want that ordering, not as a default.

## How commands run

Each command is invoked as `/bin/sh -c <command>`. Use the shell as you would in `~/.zshrc`:

- `&&`, `||`, pipes, redirects all work.
- Use absolute paths (`/usr/local/bin/foo`) or rely on the inherited `PATH`.
- Hooks run as your user. They are not sandboxed.

### Execution model

| Hook               | Sync command           | Async command           |
| ------------------ | ---------------------- | ----------------------- |
| `app.on_launch`    | Blocks the launch flow | Runs in the background  |
| `session.on_start` | Blocks until done      | Runs in the background  |
| `session.on_exit` | Blocks until done      | Runs in the background  |
| `app.on_quit`     | Blocks until done       | Forced sync (see below) |

`app.on_quit` is special: every command runs synchronously regardless of its `sync` flag, against a shared **2 second total budget**. Async commands started during quit would be orphaned by the exiting process anyway, so they are forced sync to give them a real chance to finish before exit.

Each command also has its own timeout (5s sync default, 30s async default, or the value of `timeoutSeconds`). Whichever fires first wins.

## Context environment variables

Liney exports a few variables for every hook:

| Variable                  | Set on             | Value                                                |
| ------------------------- | ------------------ | ---------------------------------------------------- |
| `LINEY_HOOK`              | All                | The hook name (e.g. `session.on_start`)              |
| `LINEY_APP_VERSION`       | All                | The Liney version                                    |
| `LINEY_SESSION_ID`        | `session.*`        | The session UUID (lowercase, dashed)                 |
| `LINEY_SESSION_CWD`       | `session.*`        | The session's effective working directory            |
| `LINEY_SESSION_SHELL`     | `session.*`        | The launch path (shell, ssh, agent binary, etc.)     |
| `LINEY_SESSION_BACKEND`   | `session.*`        | One of `localShell`, `ssh`, `agent`, `tmuxAttach`    |
| `LINEY_SESSION_EXIT_CODE` | `session.on_exit`  | Process exit code, if Liney captured one             |

The full process environment of Liney itself is also inherited, so `$HOME`, `$PATH`, `$USER`, etc. are available.

## Logging

Every hook invocation is appended to `~/.liney/hook.log` along with timing breakdown:

```
2026-05-01T20:42:17.345Z hook config: loaded 3 commands in 1ms
2026-05-01T20:42:17.346Z hook session.on_start [async]: spawn=2ms total=14ms exit=0 cmd="echo hi"
2026-05-01T20:42:18.001Z hook session.on_start [sync]: spawn=3ms total=42ms exit=0 cmd="load-project-env"
2026-05-01T20:42:30.500Z hook app.on_quit [blocking]: spawn=2ms total=512ms exit=0 cmd="rsync ..."
```

Fields:

- **mode** — `sync`, `async`, or `blocking` (`app.on_quit` only).
- **spawn** — time from `Process.run()` until the child began running. Useful for spotting fork-related slowness.
- **total** — total wall-clock time from invocation to completion.
- **exit** — process exit code. Anything non-zero or a `timeout` marker also writes the first 400 bytes of stderr / stdout for debugging.

The `hook config: loaded N commands in Mms` line fires only when the runner actually re-reads `hooks.json` — i.e., on first use and whenever the file's mtime changes. Cache hits are silent.

The log is capped at 256 KB; older lines are trimmed when the cap is reached.

Open it from **Settings → Hooks → Open hook.log**, or `tail -f ~/.liney/hook.log` from any terminal.

## Recipes

### Resume Claude Code automatically

```json
{
  "hooks": {
    "session.on_start": [
      { "enabled": true, "command": "claude --resume || true" }
    ]
  }
}
```

The `|| true` swallows the non-zero exit when there is nothing to resume, keeping `hook.log` clean.

### Notify on session exit

```json
{
  "hooks": {
    "session.on_exit": [
      { "enabled": true, "command": "osascript -e 'display notification \"Session exited\" with title \"Liney\"'" }
    ]
  }
}
```

### Boot a background service on app launch

```json
{
  "hooks": {
    "app.on_launch": [
      { "enabled": true, "command": "launchctl load ~/Library/LaunchAgents/dev.local.tunnel.plist 2>/dev/null || true" }
    ]
  }
}
```

### Save a per-session log

```json
{
  "hooks": {
    "session.on_start": [
      { "enabled": true, "command": "echo \"[$LINEY_SESSION_ID] $(date) start cwd=$LINEY_SESSION_CWD\" >> ~/liney-sessions.log" }
    ],
    "session.on_exit": [
      { "enabled": true, "command": "echo \"[$LINEY_SESSION_ID] $(date) exit code=$LINEY_SESSION_EXIT_CODE\" >> ~/liney-sessions.log" }
    ]
  }
}
```

## Security notes

- Hooks run any command as your user. Treat `hooks.json` as a sensitive file.
- The master toggle is off by default. Enable it only after reviewing the file.
- If you sync your home directory across machines, keep hooks reviewed when pulling new versions.

## Troubleshooting

- **Nothing fires.** Confirm **Settings → Hooks → Enable lifecycle hooks** is on, and that the command's `enabled` field is `true`.
- **A command runs locally but not via Liney.** Liney inherits the GUI process environment, which differs from a login shell. Source what you need explicitly inside the command, e.g. `bash -lc 'mycli ...'`.
- **`hooks.json` was edited but old commands keep running.** Liney watches the file modification time; switching the master toggle off and back on also forces a reload.
- **App quit feels slow after enabling hooks.** Reduce the work in `app.on_quit`, or move it to `app.on_launch` of the *next* run.
